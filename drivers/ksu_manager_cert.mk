# crosshatch: the KernelSU-Next manager here is preinstalled as a system app
# and gets resigned with this ROM's own platform release key during build,
# so it does not carry upstream's release manager cert. Computed via:
# keytool -printcert -jarfile ksu33.apk -rfc | openssl x509 -outform DER |
# wc -c / sha256sum. See extraAPKs/ksu33_manager_cert.sh.
KSU_NEXT_MANAGER_SIZE := 0x39e
KSU_NEXT_MANAGER_HASH := e0951ae17bedc0763b81f55c141b5aa0ed3157e30db4be62589182b39b772f42
