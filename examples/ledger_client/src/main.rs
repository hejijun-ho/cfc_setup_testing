// Copyright 2024 The Project Oak Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Rust-based client using Micro RPC to interact with the Ledger.

use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use prost_types::{Duration, Timestamp};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

// Crypto libraries
use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes128Gcm, Nonce,
};
use hpke_rs::{Hpke, Kem, Pk, Serializable};

// Oak libraries for attestation and transport
use oak_attestation_verification::AttestationVerifier;
use oak_client::{
    create_oak_client, OakClient,
    oak_client::transport::{EvidenceProvider, GrpcTransport},
};
use oak_proto_rust::oak::attestation::v1::{Evidence, Endorsements};

// Import the generated Micro RPC client.
// The name `ledger_micro_rpc` comes from the BUILD file.
use ledger_micro_rpc::fcp::confidentialcompute::{
    LedgerClient,
    CreateKeyRequest,
};

// --- Configuration ---
const LEDGER_SERVER_ADDRESS: &str = "http://localhost:8080"; // Assumes the Oak Launcher is at this address
const PLAINTEXT_MESSAGE: &[u8] = b"hello world!";

// --- CBOR/COSE Structs (same as before) ---
#[derive(Debug, Deserialize)]
struct CoseKey {
    #[serde(rename = "1")]
    kty: i64,
    #[serde(rename = "3")]
    alg: Option<i64>,
    #[serde(rename = "-1")]
    crv: i64,
    #[serde(rename = "-2")]
    x: Vec<u8>,
}

#[derive(Debug, Deserialize)]
struct CwtPayload {
    #[serde(rename = "-65537")]
    cose_key: CoseKey,
}

// --- JSON Output Struct (same as before) ---
#[derive(Debug, Serialize)]
struct EncryptedPayload {
    encrypted_data_b64: String,
    data_encryption_nonce_b64: String,
    hpke_encapsulated_key_b64: String,
    wrapped_symmetric_key_ciphertext_b64: String,
}

// The RPC call logic is now part of the main function, as it depends on the initialized client.

fn extract_raw_public_key(cose_key: &CoseKey) -> Result<Vec<u8>> {
    // This function remains the same as before.
    if cose_key.kty != 1 { return Err(anyhow!("COSE_Key is not an Octet Key Pair (OKP)")); }
    if cose_key.crv != 6 { return Err(anyhow!("COSE_Key is not for curve X25519")); }
    Ok(cose_key.x.clone())
}

fn encrypt_payload(
    ledger_hpke_public_key_bytes: &[u8],
    plaintext: &[u8],
) -> Result<EncryptedPayload> {
    // This function remains the same as before.
    let data_symmetric_key = Aes128Gcm::generate_key(&mut OsRng);
    let cipher = Aes128Gcm::new(&data_symmetric_key);
    let nonce = Nonce::from_slice(b"uniquenonce-");
    let encrypted_data = cipher.encrypt(nonce, plaintext).context("AES-GCM encryption failed")?;

    let kem = Kem::X25519HkdfSha256;
    let kdf = hpke_rs::Kdf::HkdfSha256;
    let aead = hpke_rs::Aead::Aes128Gcm;
    let hpke = Hpke::new(hpke_rs::Mode::Base, kem, kdf, aead);

    let recipient_public_key = Pk::new(kem, ledger_hpke_public_key_bytes.to_vec()).context("Invalid public key bytes")?;
    let (enc, wrapped_symmetric_key_ciphertext) = hpke.seal(&recipient_public_key, &[], Some(&data_symmetric_key.to_vec())).context("HPKE seal operation failed")?;

    Ok(EncryptedPayload {
        encrypted_data_b64: BASE64.encode(&encrypted_data),
        data_encryption_nonce_b64: BASE64.encode(nonce.as_slice()),
        hpke_encapsulated_key_b64: BASE64.encode(&enc),
        wrapped_symmetric_key_ciphertext_b64: BASE64.encode(&wrapped_symmetric_key_ciphertext),
    })
}

#[tokio::main]
async fn main() -> Result<()> {
    println!("Starting Rust ledger client with Micro RPC...");

    // Step 1: Create a low-level gRPC transport to the Oak Launcher.
    let grpc_transport = GrpcTransport::new(LEDGER_SERVER_ADDRESS)
        .await
        .context("failed to create gRPC transport")?;

    // Step 2: Create an attestation verifier.
    // In a real client, you would load reference values for the verifier.
    // For this example, we use an empty verifier, which will accept any evidence.
    // THIS IS INSECURE AND FOR DEMONSTRATION PURPOSES ONLY.
    let verifier = AttestationVerifier::new(&[], &[]);

    // Step 3: Create the attested, encrypted OakClient. This performs remote attestation.
    println!("Performing attestation and creating OakClient...");
    let mut oak_client = create_oak_client(grpc_transport, &verifier)
        .await
        .context("failed to create Oak Client")?;
    println!("OakClient created successfully.");

    // Step 4: Instantiate the generated Micro RPC client with the OakClient as the transport.
    let mut ledger_rpc_client = LedgerClient::new(oak_client);

    // Step 5: Call the `create_key` RPC via Micro RPC.
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
    let request = CreateKeyRequest {
        now: Some(Timestamp { seconds: now.as_secs() as i64, nanos: now.subsec_nanos() as i32 }),
        ttl: Some(Duration { seconds: 3600, nanos: 0 }),
    };

    println!("Calling CreateKey RPC via Micro RPC...");
    let response = ledger_rpc_client
        .create_key(&request)
        .await
        // The first layer of error is for the transport.
        .map_err(|e| anyhow!("Transport error: {:?}", e))?
        // The second layer is the application-level status.
        .context("Application-level error in CreateKey RPC")?;

    // Step 6: Parse the CWT/COSE_Key from the response (same logic as before).
    println!("Successfully received CWT, parsing...");
    let cwt: ciborium::value::Value = ciborium::from_reader(&response.public_key[..])?;
    let cwt_payload_bytes = cwt.as_array().and_then(|arr| arr.get(2)).and_then(|val| val.as_bytes()).ok_or_else(|| anyhow!("Could not extract CWT payload bytes"))?;
    let cwt_payload: CwtPayload = ciborium::from_reader(&cwt_payload_bytes[..])?;
    let cose_key = cwt_payload.cose_key;
    println!("Successfully parsed COSE_Key from CWT.");

    // Step 7 & 8: Extract key and encrypt payload (same logic as before).
    let raw_public_key = extract_raw_public_key(&cose_key)?;
    let encrypted_payload = encrypt_payload(&raw_public_key, PLAINTEXT_MESSAGE)?;

    let json_output = serde_json::to_string_pretty(&encrypted_payload)?;

    println!("\n--- Encrypted Payload (JSON format) ---");
    println!("{}", json_output);
    println!("---------------------------------------");

    Ok(())
}