{
  description = "Logos bitcoin_wallet_ui: the Bitcoin wallet app. Takes no password and holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Follows this builder: a skewed generated ABI crashes in provider init.
    bitcoin_wallet_backend = {
      url = "github:logos-co/logos-bitcoin-wallet-backend";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
