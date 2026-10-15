{
  description = "A stand-in signer_manager_module for the Bitcoin wallet app's doctest: a fixed account roster, nothing behind it.";

  inputs.logos-module-builder.url = "github:logos-co/logos-module-builder";

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
