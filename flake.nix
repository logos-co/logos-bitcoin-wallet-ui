{
  description = "Logos bitcoin_wallet_ui: the Bitcoin wallet app. Takes no signing password and holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # bitcoin_wallet_backend is reached through contracts/, named by dependency_overrides.
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
