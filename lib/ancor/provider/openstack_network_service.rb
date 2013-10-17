require 'fog'

module Ancor
  module Provider
    class OpenStackNetworkService < NetworkService
      
      def create_network(connection,network)
        provision_network connection,network
        provision_subnet  connection,network
        attach_router_interface connection,network
      end

      def terminate_network(connection,network)
        puts "TO DO - terminate network and related subnets"
        raise NotImplementedError
      end 


      def provision_network(connection,network)
        options = {
          name: network.name
        }

        provider_network = connection.networks.create options

        network.provider_details["network_id"] = provider_network.id
        network.save
      end


      def provision_subnet(connection,network)
        options = {
          network_id: network.provider_details["network_id"],
          cidr: network.cidr,
          ip_version: network.ip_version,
        }

        provider_subnet = attempt do
          connection.subnets.create options
        end

        network.provider_details["subnet_id"] = provider_subnet.id
        network.save
      end


      def attach_router_interface(connection,network)
        router_id = network.provider_details["router_id"]
        subnet_id = network.provider_details["subnet_id"]

        attempt do
          connection.add_router_interface router_id, subnet_id
        end
      end

    end # OpenStackNetworkService
  end 
end