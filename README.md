# Hemlis

Hemlis is a NixOS module to help you install secrets to your NixOS system.

It is not a turn-key solution, but a tool to copy secrets to designated locations, and reference them from Nix in a unified way

Popular Nix secrets solutions such as agenix and sopsnix requires you to manage your secrets using their designated file formats and encryption methods. They then store the secrets in the nix store in encrypted form, and decrypts them at the activation step.

Hemlis leaves the secrets management part up to you - where you store them, how you encrypt them - but helps you to copy them to the final location, and to reference them using Nix. You may find this a simpler approach, especially when you are new to Nix. The intent with this approach is that it should be simple to understand and adapt. 

# Example

To illustrate how it works, we first look at how you will refer to the secret from your Nix configuration

## Use the secret in nix
We will use setting the wifi password as an example.

To set the wifi password in nix, you need to configure

    networking.wireless.secretsFile = "/path/to/file/with/wifi/secret";

The contents of this file could be for example

    HOME_WIFI_PASSWORD=Pa$sw0rd

To configure this using Hemlis, you define a secret hemlis.secrets.home_wifi like:

    hemlis.secrets.home_wifi = {
      shellExpr = ''HOME_WIFI_PASSWORD=$home_wifi_password'';
    };

Then you refer to the the location  where this secret will be as below

    networking.wireless = {
      secretsFile = "${config.hemlis.secrets.home_wifi.path}";
      networks."knut" = {
        pskRaw = "ext:HOME_WIFI_PASSWORD";
      };
    };

Hemlis will resolve config.hemlis.secrets.home_wifi.path to a string, such as "/persist/secrets/home_wifi". A string like this is what networking.wireless.secretsFile expect. 

The contents of the file is defined by the value of shellExpr in the home_wifi attribute set value. This is a kind of template, where the part that looks like shell variable syntax will be replaced with the actual secret. 

If the $home_wifi_password is defined to Pa$sw0rd, then the result will be that the file contents will be 

    HOME_WIFI_PASSWORD=Pa$sw0rd

But how do you provide the value for the secret securely? This is explained in the following section

## Defining and installing the secret

When you build your NixOS configuration, hemlis will generate a bash script called hemlis-install, which knows how to deploy the hemlis secrets you have defined. You need to call this file with your secrets, and it will install them in the location defined in you Nix file

The hemlis-install script works on secrets deined with shell variable syntax of the form secretname="secretvalue". So when you execute the script, you should do it so those such variables are in scope for the script.

In the simplest case, which would not be secure, you can create a simple text file which defines your secrets.

Imagine a file called secrets.txt containing

    home_wifi_password="Pa$sw0rd"

If you would then execute

    source secrets.txt
    hemlis-install

It will install them. This works, but since the secrets are now present in your environment, it is not very secure. 

Another way would be to create a script call secrets.sh containing

    #!/usr/bin/env bash
    home_wifi_password="Pa$sw0rd"

    source $(readlink -f hemlis-install)

If you then execute secrets.sh, the secrets will be installed. In this case, the shell variable is defined within the shell process, and would not leak to the environment. It is however an ugly practise mix the definition of secrets with program code, and the secret would not be encrypted at rest.

A good practise is instead as follows. Deine the secrets using a password management tool. For example, using the pass password manager (https://www.passwordstore.org/), you store the secret nixos-secrets with contents as  

    home_wifi_password="Pa$sw0rd"

You can then execute

    (set -e; pass nixos-secrets && echo "source $(type hemlis-install)") | sudo bash -s

This command will let pass decrypt your secret, and combine the output with a statement to source the hemlis-install script. The result will be a script that is piped to standard input of another bash process that executes it. This is way the secrets are not stored in plaintext and do not pollute the environment

To deploy the secrets remotely, you can modfiy the command to run the installation part using ssh  

    (set -e; pass nixos-secrets && echo "source $(type hemlis-install)") | ssh remote-host sudo bash -s

## FAQ

### How do I control what permissions my secret files are installed with?

Hemlis supports owner, group and mode configuration. Example: 

    hemlis.secrets.mpd_readonly_password = {
        shellExpr = "$mpd_readonly";
        owner = "mpd";
        group = "mpd";
        mode = "440";
    };

### What are the disadvantages with this approach compared with example agenix?

The hemlis approach decouples the lifecycle of secrets management from Nix. When you change a secret, Nix will not be aware of it, and can for example not restart the services that use the secret. 

When you use agenix, change of a secret will be noticed by Nix so it will know to handle dependent components, but with hemlis, you need to take care of this yourself

This also means, that the first time you introduce a new secret, you will only have the updated hemlis-install script generated after activation. When services start up the first time, the new secrets is not yet installed.

You can either just install the secrets, and restart the dependent services. Or you can build the NixOS configuration, but not activate it. You run the new version of the hemlis-install script, and then activate the new generation. It could look like this:

    result_link="result-$(date +%s)"
    nix build ".#nixosConfigurations.hostname.config.system.build.toplevel" --out-link "$result_link"
    system_path=$(readlink -f "$result_link")
    (set -e; pass nixos-secrets && echo "source $($system_path//sw/bin/hemlis-install)") | sudo bash -s
