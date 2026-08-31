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

# /product/app/<Module>/<Module>.apk doesn't encode the package name in its
# path (no "<pkg>-<hash>" segment for crown_manager()'s path parsing to find),
# so it needs the real package name given explicitly - see the
# get_pkg_from_apk_path fallback in kernel/manager/throne_tracker.c.
KSU_MANAGER_PACKAGE := com.rifsxd.ksunext
