## What is ANCOR?

ANCOR is a framework that captures the high-level user requirements and translates them into a working IT system on a cloud infrastructure.

ANCOR can be used as a [Moving Target Defense](http://www.arguslab.org/mtd.html) platform for the systems it is deploying and managing.

[Compiling Abstract Specifications into Concrete Systems—Bringing Order to the Cloud](https://www.usenix.org/conference/lisa14/conference-program/presentation/unruh)

[Current Ancor Prototype Desciption ](https://dl.dropboxusercontent.com/u/88202830/ANCORAll-in-one.pdf)

[Puppet Manifests' Repository for ANCOR Example Scenarios](https://github.com/arguslab/ancor-puppet)

**Please don't hesitate to contact the owners if you have any questions or concerns.**

## General Requirements

- In order to use ANCOR, the user needs an Openstack cloud infrastructure that the ANCOR VM can reach.

- The ANCOR VM should be reachable by the instances running on the OpenStack infrastructure (ANCOR VM should run in bridged mode).

- The necessary Puppet manifests that are needed for the system that will be deployed with ANCOR.


## Setting Up and Using ANCOR

### Option 1 - Preconfigured ANCOR VM

1. **Download** the **ANCOR VM**:
 - Source 1 -- [OVA format (works with Virtual Box, VMware products, etc.)](https://dl.dropboxusercontent.com/u/88202830/ancor_vm.ova)
 - Source 2 -- [OVA format (works with Virtual Box, VMware products, etc.)](https://drive.google.com/open?id=0B0vt6z9-IhD9SHZQRkdaeDZIUmc)

 Default credentials - user: **ancor** password: **ancor**

 The virtual machine is bridged to the network and therefore the user might be warned that a different NIC is used than the one that it was configured on.

2. Setup the communication between ANCOR and the OpenStack deployment. Start ANCOR ... 

  Run in terminal:
  ```
  cd ~/workspace/ancor
  bin/interactive-setup
  bin/finish-setup
  bin/start-services
  ```  

**Testing ANCOR with a basic ["Drupal deployment"](https://github.com/arguslab/ancor-puppet/tree/master/modules/role/manifests/drupal) example:**

  Run in terminal:
  ```
  ancor environment plan /home/ancor/workspace/ancor/spec/fixtures/arml/drupal.yaml
  ancor environment commit
  ```
For more information about the available sample scenarios please check [Puppet Manifests' Repository for ANCOR Example Scenarios](https://github.com/arguslab/ancor-puppet)

For more features (e.g., adding, removing, replacing instances) run in terminal: 
```
ancor
```

### Option 2 - Using [Vagrant](http://www.vagrantup.com/)

1. Install [Vagrant](http://www.vagrantup.com/)
2. Clone the ANCOR repository. Run in terminal: 

 ```
 git clone https://github.com/arguslab/ancor/ && cd ancor
 ```
3. Create a local development VM for ANCOR. All necessary ports are forwarded to your host, so you can use your development machine's IP address when configuring ANCOR. Run in terminal: `vagrant up`

4. Once the VM is up and running, run in terminal:`vagrant ssh`
5. Run the following commands inside the VM to configure and start ANCOR:

  `cd /vagrant` to change into the ANCOR directory 
  This directory is shared between the VM and your host using the
  Shared Folders feature in VirtualBox. Changes in this directory will be shared instantly between the VM
  and your host.

  `bin/interactive-setup` to start from the configuration template

  `bin/setup-mcollective` to install MCollective for ANCOR

  `bin/start-services` to start the Rails app and Sidekiq worker for ANCOR
6. Test ANCOR with a basic ["Drupal deployment"](https://github.com/arguslab/ancor-puppet/tree/master/modules/role/manifests/drupal) example:

 ```
 ancor environment plan /vagrant/spec/fixtures/arml/drupal.yaml; ancor environment commit
 ```
 For more information about the available sample scenarios please check [Puppet Manifests' Repository for ANCOR Example Scenarios](https://github.com/arguslab/ancor-puppet)

### Option 3 - General Setup Instructions (for advanced users)
This framework is developed on Ubuntu 12.04 x64.

- Ensure your terminal of choice is using bash/zsh as a [login shell](https://rvm.io/support/faq)

- Please follow the [automated installer](https://github.com/arguslab/ancor-environment) (includes the [ANCOR CLI](https://github.com/arguslab/ancor-cli) tool)

- Run in terminal: Change directory into the ANCOR folder to configure and start ANCOR

  ```bin/interactive-setup; bin/setup-mcollective; bin/start-services```
- If needed, install [ANCOR CLI](https://github.com/arguslab/ancor-cli) on a different host

