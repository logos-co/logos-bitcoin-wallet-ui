cmake_minimum_required(VERSION 3.14)
project(BitcoinWalletUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME bitcoin_wallet_ui
    REP_FILE src/bitcoin_wallet_ui.rep
    SOURCES
        src/bitcoin_wallet_ui_backend.h
        src/bitcoin_wallet_ui_backend.cpp
        src/qrcodegen.hpp
        src/qrcodegen.cpp
    INCLUDE_DIRS
        src
)
