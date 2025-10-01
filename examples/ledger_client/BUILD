load("@rules_rust//rust:defs.bzl", "rust_binary")
load("//bazel:rust_micro_rpc.bzl", "rust_micro_rpc_library")  ## not found
# load("@rules_rust//rust:defs.bzl", "rust_library")
# rust_library(
#     name = "micro_rpc",
#     srcs = glob(["src/*.rs"]),
#     proc_macro_deps = [
#         "@oak_crates_index//:async-trait",
#         "@oak_crates_index//:prost-derive",
#     ],
#     target_compatible_with = any_platform([
#         "//:aarch64-apple-setting",
#         "//:x86_64-linux-setting",
#         "//:x86_64-none-setting",
#         "//:x86_64-none-no_avx-setting",
#         "//:wasm32-none-setting",
#     ]),
#     deps = [
#         ":build",
#         "@oak_crates_index//:prost",
#     ],
# )

# Generate the Micro RPC client stub for the ledger service.
rust_micro_rpc_library(
    name = "ledger_micro_rpc",
    proto_path = "//fcp/protos/confidentialcompute:ledger.proto",
    deps = [
        "@com_google_protobuf//:duration_proto",
        "@com_google_protobuf//:timestamp_proto",
        "@oak//proto/attestation:endorsement_proto",
        "@oak//proto/attestation:evidence_proto",
        "@oak//proto/micro_rpc:options_proto",
    ],
)

# Define the client binary itself.
rust_binary(
    name = "ledger_client",
    srcs = ["src/main.rs"],
    deps = [
        # The generated Micro RPC client for the ledger.
        ":ledger_micro_rpc",
        # The underlying transport and verifier.
        "//oak_client",
        "//oak_crypto",
        # The Micro RPC runtime library.
        "//micro_rpc",
        # Other necessary crates.
        "@oak_crates_index//:anyhow",
        "@oak_crates_index//:base64",
        "@oak_crates_index//:ciborium",
        "@oak_crates_index//:clap",
        "@oak_crates_index//:futures",
        "@oak_crates_index//:hpke-rs",
        "@oak_crates_index//:prost",
        "@oak_crates_index//:serde",
        "@oak_crates_index//:serde_json",
        "@oak_crates_index//:tokio",
        # Tonic is still needed for the base transport layer to the Oak Launcher.
        "@oak_crates_index//:tonic",
        "@oak_crates_index//:aes-gcm",
        # Dependencies for the attestation verifier
        "//oak_attestation_verification",
        "//oak_proto_rust",
    ],
)
