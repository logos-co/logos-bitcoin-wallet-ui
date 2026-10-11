{
  description = "A scripted bitcoin_wallet_backend for the Bitcoin wallet app's doctest: the real contract, nothing behind it.";

  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
