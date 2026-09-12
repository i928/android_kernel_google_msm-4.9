# crosshatch: the KernelSU-Next manager here is preinstalled as a /product
# system app, signed with its own dedicated cert (device/google/crosshatch/
# security/ksu_manager/) rather than default_dev_cert -- a shared
# default_dev_cert collided with other resigned /product apps (e.g.
# Aperture) and let the kernel's manager scan crown the wrong app entirely.
# Same keystore identity as the manually-installed build on other devices;
# see ~/ksu-manager-build/README.md. Computed via:
# apksigner verify --print-certs + manual v2 signing-block cert extraction.
KSU_NEXT_MANAGER_SIZE := 0x2ea
KSU_NEXT_MANAGER_HASH := b22ee43b209e087273ecd9fc2d2b21f0cf58df0f37ded0694d3132ef8dcc6fb4

# NO second trusted cert. There used to be one here (size 0x39e, hash
# e0951ae17bedc0763b81f55c141b5aa0ed3157e30db4be62589182b39b772f42) for the
# standalone upstream KSU-Next release APK, with a comment calling the risk a
# known tradeoff: "trusting it means ANY app resigned with this same shared key
# on this ROM would also get crowned as manager".
#
# That is exactly what happened. e0951ae1 is not the upstream project's key at
# all -- it is this ROM's own release key (DN "EMAILADDRESS=android@android.com,
# CN=ReleaseKey, OU=Android, O=CustomROM"), so EVERY app built into the ROM
# matches it. The boot scan crowns whichever one it reaches first:
#
#   KernelSU: sha256: e0951ae1..., expected: e0951ae1...
#   KernelSU: Found new base.apk at path: /product/app/Aperture/Aperture.apk, is_manager: 1
#   KernelSU: manager pkg: dev.i928.mgr
#   KernelSU: Crowning manager: dev.i928.mgr(uid=10384)
#
# Aperture (the camera) matched. It survived only because /product/app paths
# carry no package name, so get_pkg_from_apk_path() falls back to
# KSU_MANAGER_PACKAGE and the uid lookup lands on the real manager anyway. Any
# ROM-signed app under /data/app parses its own real package name out of the
# path instead, crowns that uid, and the manager then reports
# "Unsupported | Not integrated" because the kernel thinks something else wears
# the crown.
#
# The dedicated cert above is unique to the manager APK and is all that should
# ever be trusted. The KSU_NEXT_MANAGER_*_2 mechanism itself still exists in the
# submodule's Kbuild/apk_sign.c and stays inert while nothing defines it.

# /product/app/<Module>/<Module>.apk doesn't encode the package name in its
# path (no "<pkg>-<hash>" segment for crown_manager()'s path parsing to find),
# so it needs the real package name given explicitly - see the
# get_pkg_from_apk_path fallback in kernel/manager/throne_tracker.c.
#
# Renamed 2026-09-11 from com.rifsxd.ksunext to dev.i928.mgr to match sunfish
# (kernel commit 7bfc18e) so all three devices share ONE hardened manager APK
# (applicationId + code namespace both dev.i928.mgr; the cert b22ee43b pinned
# above is unchanged, so no cert re-pin needed). Root/manager detectors keying
# on the well-known KernelSU-Next package name no longer find the baked manager.
# Requires the dev.i928.mgr manager APK (~/ksu-manager-build) in this device's
# /product prebuilt -- rebuild kernel to bake this pin, and ROM to bake the APK.
KSU_MANAGER_PACKAGE := dev.i928.mgr
