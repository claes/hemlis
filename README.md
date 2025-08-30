# Hemlis

Hemlis is a NixOS module to help you install secrets to your NixOS system.

It is not a turn-key solution, but a tool to copy secrets to designated locations, and reference them from Nix in a way that avoids copying them to the Nix store. You can use it together with your already established secrets management practises. For example, you can combine it with your password manager.

Popular Nix secrets solutions such as agenix and sopsnix requires you to manage your secrets using their designated file formats and encryption methods. They then store the secrets in the nix store in encrypted form, and decrypts them at the activation step. You may find this cumbersome, complex or hard to understand. In that case, Hemlis may be for you. 

Hemlis leaves the encryption part up to you - where you keep them, how you encrypt them in their master location. What hemlis helps you with is to copy them to the final location, and to reference them using Nix. You may find this a simpler approach, especially when you are new to Nix. The intent with this approach is that it should be simple to understand and adapt to your needs.

# Example

To illustrate how it works, we first look at how you will refer to the secret from your Nix configuration

## Use the secret in nix
We will use setting the wifi password as an example.

To set the wifi password in nix, you need to configure

    networking.wireless.secretsFile = "/path/to/file/with/wifi/secret";

The contents of this file could be for example

    HOME_WIFI_PASSWORD=Pa$sw0rd

It is the Pa$sw0rd which is the secret. The other part is just a boilerplate, which is needed for this particular wifi use case. 

To configure this using Hemlis, you define a secret hemlis.secrets.home_wifi like:

    hemlis.secrets.home_wifi = {
      template = ''HOME_WIFI_PASSWORD=$home_wifi_password'';
    };

As you can see, Pa$sw0rd is here replaced with $home_wifi_password. How this will work is explained later. 
Then you refer to the the location where this secret will be installed as below:

    networking.wireless = {
      secretsFile = "${config.hemlis.secrets.home_wifi.path}";
      networks."home_wifi" = {
        pskRaw = "ext:HOME_WIFI_PASSWORD";
      };
    };

(You can ignore the networks."home_wifi" part, it is also just for this particular use case.)

Nix will resolve config.hemlis.secrets.home_wifi.path to a string, such as "/persist/secrets/home_wifi". A string like this is what the networking.wireless.secretsFile option expects. 

This part is actually quite similar to for example agenix. But it differs how the secrets are defined:

The contents of the file is defined by the value of template in the home_wifi attribute set value. This is a kind of template, where the part that looks like shell variable syntax will be replaced with the actual secret, by hemlis. 

If the $home_wifi_password is defined to be Pa$sw0rd, then the result will be that the file contents will be 

    HOME_WIFI_PASSWORD=Pa$sw0rd

But how do you provide the value for $home_wifi_password securely? This is explained in the following section!

## Defining and installing the secret

When you build your NixOS configuration, hemlis will generate a bash script called hemlis-install, which knows how to deploy the hemlis secrets you have defined. You need to call this script with your secrets, and it will install them to a location that will be used in the Nix config. 

The hemlis-install script works on secrets defined with shell variable syntax of the form secretname="secretvalue". When you execute the script, you should do it so such variables are in scope for the script.

In the simplest case (which would not be secure!) you can create a simple text file which defines your secrets.

Imagine a file called secrets.txt containing

    home_wifi_password="Pa$sw0rd"

If you would then execute

    source secrets.txt
    hemlis-install

hemlis-install will match the home_wifi_password variable with the $home_wifi_password expression given in the template Nix option. The result will be a file containing HOME_WIFI_PASSWORD=Pa$sw0rd which config.hemlis.secrets.home_wifi.path will be referencing.

This works, but since the secrets are now present in your environment as environment variables, it is very insecure. It is also a bad practise to store secrets in plain text files - but this was just for illustration. 

Another way would be to create a script call secrets.sh containing

    #!/usr/bin/env bash
    home_wifi_password="Pa$sw0rd"

    source $(type hemlis-install)

If you then execute secrets.sh, the secrets will be installed. In this case, the shell variable is defined within the shell process, and would not leak to the environment. It is however an ugly practise mix the definition of secrets with program code, and also here the secret would not be encrypted at rest. So neither this is how you should do it! 

We need to create a way to combine the secrets with the hemlis-install invocation dynamically, without leaking the secrets outside the installation process, and without storing the secrets unencrypted. 

This can be done as follows:

Define the secrets using a password management tool. For example, using the pass password manager (https://www.passwordstore.org), you can store the pass secret "nixos-secrets" with contents as  

    home_wifi_password="Pa$sw0rd"

just like the contents of the plain text file in the first example. 

You will then let pass decrypt the file when you want to install the secrets:

    (set -e; pass nixos-secrets && echo "source $(type hemlis-install)") | sudo bash -s

This command will let pass decrypt your secrets, and combine the output with a statement to source the hemlis-install script. The result will be a script, that is very similar to the second example, that is piped to standard input of another bash process that executes it. This way the secrets are not stored in plaintext and do not pollute the environment. 

To deploy the secrets remotely, you can modfiy the command to run the installation part using ssh  

    (set -e; pass nixos-secrets && echo "source $(type hemlis-install)") | ssh remote-host sudo bash -s

You can adapt this approach to fit you. If you don't use pass password management tool, you can use encryption tools such as gpg or age, or explore ways to use another password manager. Create a way to decrypt your secrets from rest, format them in the shell variable syntax, and combine them with hemlis-install. 

## FAQ

### How do I control what permissions my secret files are installed with?

Hemlis supports owner, group and mode configuration. Example: 

    hemlis.secrets.mpd_readonly_password = {
        template = "$mpd_readonly";
        owner = "mpd";
        group = "mpd";
        mode = "440";
    };

### How do I set where my secrets are installed

You can set the secretsDir path as follows
    
    hemlis.secretsDir.path = "/my-secrets-dir";

### What are the disadvantages with this approach compared with example agenix?

The hemlis approach decouples the lifecycle of secrets management from Nix. When you change a secret, Nix will not be aware of it, and can for example not restart the services that use the secret. 

When you use agenix, change of a secret will be noticed by Nix so it will know to handle dependent components, but with hemlis, you need to take care of this yourself

This also means, that the first time you introduce a new secret, you will only have the updated hemlis-install script generated after activation. When services start up the first time, the new secrets is not yet installed.

You can either just install the secrets, and restart the dependent services. Or you can build the NixOS configuration, but not activate it. You run the new version of the hemlis-install script, and then activate the new generation. It could look like this:

    result_link="result-$(date +%s)"
    nix build ".#nixosConfigurations.hostname.config.system.build.toplevel" --out-link "$result_link"
    system_path=$(readlink -f "$result_link")
    (set -e; pass nixos-secrets && echo "source $($system_path//sw/bin/hemlis-install)") | sudo bash -s


### Is Hemlis secure?

Hemlis is at its core just a way to copy data to files in locations as specified with Nix, but witout Nix being aware of them. With this I mean, the Nix interpreter will only handle strings. It will not know they represent paths to files, and it will therefore not copy files to the Nix store. The actual value of the secrets are never in play in the Nix config. This is otherwise a big risk for users new to Nix. 

Hemlis does not apply any encryption itself. Since it is not a complete solution, just a building block, it can be used in secure or insecure ways.

Used well, it can definitely be secure.

- Make sure you encrypt the secrets in their master location.
- Don't use environment variables to propagate them between processes
- Use pipes for inter-process communication, do not use intermediate files. 
