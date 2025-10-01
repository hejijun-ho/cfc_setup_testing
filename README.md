# Confidential Federated Compute 執行
## pre-process
在 /mydata 掛載足夠大的硬碟，並且開啟當前user對此資夾的rwx權限，並且ledger, data-process 分別跑在兩台不同電腦上測試
## ledger TEE generation steps
### setup
```
cd cfc_setup_testing/
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
cd cfc_setup_testing/
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

### connection test / fixed_request_test (以下用 launcher_sending_test 舉例)
```
cd cfc_setup_testing/
mv ledger/WORKSPACE /mydata/google_parfait_build/confidential-federated-compute
cp ledger/ledger_sending_test/channel_fix.patch /mydata/google_parfait_build/confidential-federated-compute/third_party/oak
cp ledger/ledger_sending_test/launcher.rs /mydata/google_parfait_build/oak/oak_launcher_utils/src
./ledger/generate_ledger.sh
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