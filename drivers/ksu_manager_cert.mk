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

# Second trusted cert: the standalone official/upstream KSU-Next release APK
# (ksu33.apk), sideloaded separately for testing against the /product-baked
# build above. Its cert DN is "CN=ReleaseKey, OU=Android, O=CustomROM" -- a
# generic-looking release-key pattern, not a dedicated per-project key, so
# trusting it means ANY app resigned with this same shared key on this ROM
# would also get crowned as manager. Accepted as a known tradeoff on a
# personal test device -- do not carry this forward to a build meant for
# wider distribution without reconsidering. Computed the same way as above.
KSU_NEXT_MANAGER_SIZE_2 := 0x39e
KSU_NEXT_MANAGER_HASH_2 := e0951ae17bedc0763b81f55c141b5aa0ed3157e30db4be62589182b39b772f42

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
