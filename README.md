# Confidential Federated Compute 執行
## pre-process
在 /mydata 掛載足夠大的硬碟，並且開啟當前user對此資夾的rwx權限，並且ledger, data-process 分別跑在兩台不同電腦上測試
## ledger TEE generation steps
### setup
```
cd cfc_setup/
./ledger/ledger_v5.sh
cp ./ledger/launcher.rs /mydata/google_parfait_build/oak/oak_launcher_utils/src
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils
sudo usermod -a -G kvm $USER
## re-login here
```
### run ledger
```
./ledger/generate_ledger.sh
```
## data-process TEE generation steps
### setup
```
cd cfc_setup/
./dptee/setup_data_processing_tee.sh
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils
sudo usermod -a -G kvm $USER
## re-login here
```
### run data-process TEE
```
./dptee/run_data_processing_tee.sh
```

## examples/ 預期的使用方式 (實作對 ledger 的連線)
```
mv ./examples /mydata/google_parfait_build/oak/
cd /mydata/google_parfait_build/oak/
bazelisk run //examples/ledger_client:ledger_client
```

## test for ledger TEE connection
- 目前測試方式是用telnet 連接 ledger電腦 的 port 46787，資料輸入後telnet主動關閉連線，觀察ledger電腦的輸出
- ledger 提供的 api 來源: federated-compute/fcp/protos/confidentialcompute/ledger.proto

## 目前狀況
- SEV-ES 執行測試: 由於 launcher.rs 最初提供的 cpu架構 cmd.args(["-cpu", "IvyBridge-IBRS"]); 是必然無法順利執行 sev-es 的，因為是 Intel 的架構
- 這是我目前嘗試運行的架構，可以順利運行，雖然還沒有跑 SEV-ES
```
cmd.args([
        "-cpu", "EPYC-v4",
        "-machine", "microvm,acpi=on", // 保留 microvm
    ]);
```
- 但是以這個架構再加入跑 SEV-ES 會失敗