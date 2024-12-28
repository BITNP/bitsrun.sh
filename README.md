# bitsrun.sh
dependency: curl xxd sed grep coreutils

```
usage: login username [password]
       logout
       status
```
## OpenWrt notes

This script *cannot* run under busybox version of ash and grep. 

Run `opkg install bash xxd grep curl coreutils-base64 coreutils-sha1sum` on your router to install the dependencies.
