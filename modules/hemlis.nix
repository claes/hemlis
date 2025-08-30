{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) concatStringsSep mkOption types;

  cfg = config.hemlis;

  installSecretCmd = entries:
    concatStringsSep "\n" (map (
      entry: let
        template = entry.template;
        file = entry.file;
        mode = entry.mode or "400";
        owner = entry.owner or "root";
        group = entry.group or "root";
        skipIfExists = entry.skipIfExists or false;

        vars = extractVars template;

        checks = concatStringsSep " && " (
          (
            if skipIfExists
            then [''[[ ! -f "$SECRETS_DIR/${file}" ]]'']
            else []
          )
          ++ (map (v: ''[[ -n "${v}" ]]'') vars)
        );
      in ''
        ${checks} && install -m ${mode} \
          --owner="$(if getent passwd ${owner} > /dev/null; then echo ${owner}; else echo root; fi)" \
          --group="$(if getent group ${group} > /dev/null; then echo ${group}; else echo root; fi)" \
        /dev/stdin "$SECRETS_DIR/${file}" <<EOF
        ${template}
        EOF
      ''
    ) (builtins.attrValues entries));

  installSecrets = pkgs.writeShellScriptBin "hemlis-install" (
    let
      installSecretStatements = installSecretCmd cfg.secrets;
      secretsDir = cfg.secretsDir.path;
      dirOwner = cfg.secretsDir.owner or "root";
      dirGroup = cfg.secretsDir.group or "root";
      dirMode = cfg.secretsDir.mode or "711";
    in ''
      set -euo pipefail

      SECRETS_DIR="''${SECRETS_DIR:-${secretsDir}}"

      if [ -z "$SECRETS_DIR" ] || [ "$SECRETS_DIR" = "/" ]; then
        echo "ERROR: SECRETS_DIR is unset or dangerous ('$SECRETS_DIR')"
        exit 1
      fi

      ${pkgs.coreutils}/bin/install -d -m ${dirMode} \
        --owner="$(if getent passwd ${dirOwner} > /dev/null; then echo ${dirOwner}; else echo root; fi)" \
        --group="$(if getent group ${dirGroup} > /dev/null; then echo ${dirGroup}; else echo root; fi)" \
        "$SECRETS_DIR"

      ${pkgs.findutils}/bin/find "$SECRETS_DIR" -mindepth 1 -delete

      ${installSecretStatements}

      echo "Secrets updated in $HOSTNAME"
    ''
  );

  extractVars = str: let
    # 1. Split and keep capture groups.
    rawParts = lib.split ''(\$[A-Za-z_][A-Za-z0-9_]*)'' str;

    # 2. Flatten away the one-element sub-lists that come from captures.
    parts = lib.flatten rawParts;

    # 3. Pick only the tokens that *are* variable references.
    varsWithDollar =
      lib.filter
      (p: builtins.isString p && lib.match "^\\$[A-Za-z_][A-Za-z0-9_]*$" p != null)
      parts;

    # 4. Strip the leading ‘$’.
    names = lib.map (v: lib.substring 1 (lib.stringLength v - 1) v) varsWithDollar;

    # 5. Deduplicate deterministically.
    unique = lib.attrNames (lib.listToAttrs (lib.forEach names (n: {
      name = n;
      value = null;
    })));
  in
    unique;
in {
  options.hemlis = {
    secretsDir = mkOption {
      type = types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            default = "/persist/secrets";
            description = "Path to the directory where secrets are installed.";
          };
          owner = mkOption {
            type = types.str;
            default = "root";
            description = "Owner of the secrets directory.";
          };
          group = mkOption {
            type = types.str;
            default = "root";
            description = "Group of the secrets directory.";
          };
          mode = mkOption {
            type = types.str;
            default = "711";
            description = "Permissions for the secrets directory.";
          };
        };
      };
      default = {};
      description = "Configuration for the secrets directory.";
    };

    secrets = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: {
        options = {
          template = mkOption {
            type = types.str;
            description = "Template for the secret file. Should reference variables like \$secret for values to be replaced with actual secret value.";
          };
          file = mkOption {
            type = types.str;
            default = name;
            defaultText = ''"${name}"'';
            description = "Destination file name.";
          };
          mode = mkOption {
            type = types.str;
            default = "400";
            description = "File permissions.";
          };
          owner = mkOption {
            type = types.str;
            default = "root";
            description = "File owner.";
          };
          group = mkOption {
            type = types.str;
            default = "root";
            description = "File group.";
          };
          path = mkOption {
            type = types.str;
            default = "${cfg.secretsDir.path}/${config.file}";
            defaultText = ''
              "''${cfg.secretsDir.path}/''${config.file}"
            '';
            description = ''
              Path where the secret is installed.
            '';
          };
        };
      }));
      default = {};
      description = "Attribute set of named secrets to be installed.";
    };
  };

  config.environment.systemPackages = with pkgs; [
    installSecrets
  ];
}
