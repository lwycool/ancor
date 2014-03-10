require 'ipaddress'

module Ancor
  module Adaptor
    class AdaptationEngine
      include Loggable
      include Tasks

      PUBLIC_CIDR = '0.0.0.0/0'

      # Function that populates details for new network model objects
      # @return [Proc]
      attr_accessor :network_builder

      # Function that populates details for new instance model objects
      # @return [Proc]
      attr_accessor :instance_builder

      # @return [Proc]
      attr_accessor :public_ip_builder

      def initialize
        @network_builder = proc {}
        @instance_builder = proc {}
        @public_ip_builder = proc {}
      end

      # Queries the requirement model and creates a suitable system model
      #
      # @raise [LockAcquisitionError]
      # @param [Environment] environment
      # @return [undefined]
      def plan(environment)
        environment.synchronized do

          network = build_network
          instances = []

          Role.all.each do |role|
            role.min.times do |index|
              instances.push(build_instance(index, network, role))
            end
          end

        end
      end

      # Starts the deployment of planned networks and instances
      #
      # This method call is asynchronous
      #
      # 1. Locks the environment
      # 2. Provisions the network
      # 3. Deploys the instances
      # 4. Unlocks the environment
      #
      # @raise [LockAcquisitionError]
      # @param [Environment] environment
      # @return [undefined]
      def commit(environment)
        environment.lock

        begin
          instances = environment.roles.flat_map { |r| r.instances }
          secgroups = instances.flat_map { |i| i.security_groups }.uniq
          networks = instances.flat_map { |i| i.networks }.uniq
          public_ips = instances.map { |i| i.public_ip }.compact

          puts "Deploying #{instances.count} instances"

          build_task_chain do
            parallel do
              networks.each   { |network| task(ProvisionNetwork, network.id) }
              public_ips.each { |public_ip| task(AllocatePublicIp, public_ip.id) }
              instances.each  { |instance| task(CleanPuppetCertificate, instance.id) }
              secgroups.each  { |secgroup| task(SyncSecurityGroup, secgroup.id) }
            end

            parallel do
              instances.each  { |instance| task(DeployInstance, instance.id) }
            end

            parallel do
              public_ips.each { |public_ip| task(AssociatePublicIp, public_ip.id) }
            end

            task(UnlockEnvironment, environment.id)
          end
        rescue => ex
          # Something went wrong, unlock the environment immediately
          environment.unlock
          raise ex
        end
      end

      # @raise [LockAcquisitionError]
      # @param [Environment] environment
      # @return [undefined]
      def destroy(environment)
        environment.lock

        begin
          instances = environment.roles.flat_map { |r| r.instances }
          secgroups = instances.flat_map { |i| i.security_groups }.uniq
          networks = instances.flat_map { |i| i.networks }.uniq
          public_ips = environment.roles.flat_map { |r| r.public_ips }

          if instances.empty?
            environment.destroy
          else
            build_task_chain do
              parallel do
                instances.each  { |instance| task(DeleteInstance, instance.id) }
              end

              parallel do
                secgroups.each  { |secgroup| task(DeleteSecurityGroup, secgroup.id) }
                networks.each   { |network| task(DeleteNetwork, network.id) }
                public_ips.each { |public_ip| task(DeallocatePublicIp, public_ip.id) }
              end

              task(DeleteEnvironment, environment.id)
            end
          end
        rescue => ex
          environment.unlock
          raise ex
        end
      end

      # Adds an instance for the given role
      #
      # This method call is asynchronous
      #
      # 1. Locks the environment
      # 2. Deploys an instance
      # 3. Pushes configuration to affected instances
      # 4. Unlocks the environment
      #
      # @raise [LockAcquisitionError]
      # @param [Symbol] role_slug
      # @return [undefined]
      def add_instance(role_slug)
        role = Role.find_by(slug: role_slug)
        environment = role.environment

        environment.lock

        begin
          network = Network.first

          instance = build_instance(rand(100..10000), network, role)
          puts "Planning to deploy instance #{instance.name}"

          build_task_chain do
            parallel do
              task(CleanPuppetCertificate, instance.id)
              instance.security_groups.each { |secgroup| task(SyncSecurityGroup, secgroup.id) }
            end

            task(DeployInstance, instance.id)

            parallel do
              # TODO Update security groups for dependent instances
              role.dependent_instances.each { |instance| task(PushConfiguration, instance.id) }
            end

            if instance.public_ip
              task(AllocatePublicIp, instance.public_ip.id)
              task(AssociatePublicIp, instance.public_ip.id)
            end
          end
        rescue => ex
          # Something went wrong, unlock the environment immediately
          environment.unlock
          raise ex
        end
      end

      # Removes a given instance
      #
      # This method call is asynchronous
      #
      # 1. Locks the environment
      # 2. Marks instance for undeploy
      # 3. Pushes configuration to affected instances
      # 4. Deletes the instance
      # 5. Unlocks the enviroment
      #
      # @raise [LockAcquisitionError]
      # @param [String] instance_id
      # @return [undefined]
      def remove_instance(instance_id)
        instance = Instance.find instance_id
        role = instance.role
        environment = role.environment

        environment.lock

        begin
          puts "Planning to undeploy instance #{instance.name}"

          instance.planned_stage = :undeploy
          instance.save

          build_task_chain do
            parallel do
              # TODO Update security groups for dependent instances
              role.dependent_instances.each { |instance| task(PushConfiguration, instance.id) }
            end

            task(DeleteInstance, instance.id)

            parallel do
              instance.security_groups.each { |secgroup| task(DeleteSecurityGroup, secgroup.id) }
            end

            task(UnlockEnvironment, environment.id)
          end
        rescue => ex
          # Something went wrong, unlock the environment
          environment.unlock
          raise ex
        end
      end

      private

      def build_task_chain(&block)
        builder = ChainTaskBuilder.build(&block)

        unless builder.empty?
          # TODO This should only be enabled for debug environments
          GraphvizDumper.dump_to_tmp(*builder.heads)
          builder.heads.each do |task|
            TaskWorker.perform_async(task.id.to_s)
          end
        end
      end

      # Creates a new network model object
      # @return [Network]
      def build_network
        network = Network.new
        network.cidr = "10.#{rand(0..254)}.#{rand(0..254)}.0/24"

        @network_builder.call(network)

        network.save!
        network
      end

      # Creates a new instance model object
      #
      # @param [Integer] index
      # @param [Network] network
      # @param [Role] role
      # @return [Instance]
      def build_instance(index, network, role)
        instance = Instance.new

        # Instance host names are not allowed to have underscores
        instance.name = "#{role.slug}#{index}".dasherize
        instance.role = role
        instance.scenario = role.scenarios.first
        instance.planned_stage = :deploy

        attach_interface(instance, network)
        select_channels(instance, role.exports)
        assign_public_ip(instance, network)

        # Security groups are mapped one-to-one with instances
        secgroup = SecurityGroup.new
        update_secgroup(instance, secgroup)
        instance.security_groups.push(secgroup)

        @instance_builder.call(instance)

        instance.save!
        instance
      end

      # @param [Instance] instance
      # @param [Network] network
      # @return [undefined]
      def assign_public_ip(instance, network)
        role = instance.role

        if role.public?
          # Attempt to reuse public IPs that are already allocated
          public_ip = role.public_ips.find { |public_ip|
            public_ip.instance.nil?
          }

          unless public_ip
            public_ip = PublicIp.new
            public_ip.role = role
            @public_ip_builder.call(public_ip, instance, network)
          end

          instance.public_ip = public_ip
          public_ip.save!
        end
      end

      # Updates the rules in the given security group for the given instance
      #
      # @param [Instance] instance
      # @param [SecurityGroup] secgroup
      # @return [SecurtyGroup]
      def update_secgroup(instance, secgroup)
        blocks = if instance.public?
          [PUBLIC_CIDR]
        else
          instance.networks.map { |network| network.cidr }
        end

        targets = blocks.product(instance.channel_selections)

        rules = targets.map { |cidr, selection|
          case selection
          when SinglePortChannelSelection
            SecurityGroupRule.new(
              cidr: cidr, protocol: selection.protocol, from: selection.port, to: selection.port)
          when PortRangeChannelSelection
            SecurityGroupRule.new(
              cidr: cidr, protocol: selection.protocol, from: selection.from_port, to: selection.to_port)
          else
            raise ArgumentError
          end
        }

        secgroup.rules = rules
        secgroup.save!

        secgroup
      end

      # Attaches the given instance to the given network
      #
      # @param [Instance] instance
      # @param [Network] network
      # @return [InstanceInterface]
      def attach_interface(instance, network)
        block = IPAddress.parse(network.cidr)

        if network.last_ip
          last_ip = IPAddress.parse(network.last_ip)
          last_ip = IPAddress::IPv4.parse_u32(last_ip.to_u32 + 3)
        else
          last_ip = IPAddress::IPv4.parse_u32(block.to_u32 + 10)
        end

        unless block.include?(last_ip)
          raise "Instance IP address out of range of network block"
        end

        network.last_ip = last_ip.address
        network.save

        InstanceInterface.create!(network: network, instance: instance, ip_address: last_ip.address)
      end

      # Selects the given channels for the given instance
      #
      # @param [Instance] instance
      # @param [Enumerable] channels
      # @return [undefined]
      def select_channels(instance, channels)
        channels.each do |channel|
          instance.channel_selections.push(select_channel(channel))
        end
      end

      # Creates a channel selection for the given channel
      #
      # SinglePortChannel(tcp) -> SinglePortChannelSelection(10343)
      # PortRangeChannel(udp, 10) -> PortRangeChannelSelection(20100, 20110)
      #
      # @param [Channel] channel
      # @return [ChannelSelection]
      def select_channel(channel)
        case channel
        when SinglePortChannel
          if channel.number
            SinglePortChannelSelection.new(channel: channel, port: channel.number)
          else
            SinglePortChannelSelection.new(channel: channel, port: rand(10_000..50_000))
          end
        when PortRangeChannel
          if channel.number
            from_port = channel.number
          else
            from_port = rand(10_000..50_000)
          end
          to_port = from_port + channel.size

          PortRangeChannelSelection.new(channel: channel, from_port: from_port, to_port: to_port)
        else
          raise ArgumentError
        end
      end
    end # AdaptationEngine
  end # Adaptor
end
