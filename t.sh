run_infinity() {
    common_prep
    rm -rf .repo/local_manifests prebuilts/misc/protobuf_vendorcompat
    repo init --no-repo-verify -u https://github.com/ProjectInfinity-X/manifest -b 17 -g default,-mips,-darwin,-notdefault --git-lfs --depth=1
    git clone https://github.com/xc112lg/blossom_manifest.git -b 17 .repo/local_manifests
    curl -sf https://raw.githubusercontent.com/xc112lg/lg_releases/refs/heads/main/resync.sh | bash

export WITH_ADB_INSECURE=true 
grep -q '^[[:space:]]*# props\.append("ro\.adb\.secure=1")' build/soong/scripts/gen_build_prop.py ||
sed -i 's/^\([[:space:]]*\)props\.append("ro\.adb\.secure=1")/\1# props.append("ro.adb.secure=1")/' build/soong/scripts/gen_build_prop.py

   
    # sed -i '\|vendor/extras/prebuilt/product/fonts,\$(TARGET_COPY_OUT_PRODUCT)/fonts|d' vendor/extras/evolution.mk
    # sed -i '/<string-array name="emoji_style_entries">/,/<\/string-array>/{/emoji_style_stock/!{/<item>/d}}' packages/apps/Evolver/res/values/evolution_arrays.xml
    # sed -i '/<string-array name="emoji_style_values">/,/<\/string-array>/{/<item>android<\/item>/!{/<item>/d}}' packages/apps/Evolver/res/values/evolution_arrays.xml
    # sed -i '/fonts_customization_emoji_\(ios\|samsung\|swiftui\|facebook\)\.xml/d' vendor/extras/evolution.mk
    sed -i '/\/class\/typec.*sysfs_usb_nonplat/d' device/mediatek/sepolicy_vndr/basic/non_plat/genfs_contexts
    perl -0pi -e 's/cc_prebuilt_library_shared\s*\{\s*name:\s*"libui-v32",.*?^\}//ms' device/xiaomi/blossom/vndk/Android.bp
D=device/xiaomi/blossom/sepolicy
# type + labeling already come from the platform; vendor can't see/redeclare it
sed -i '/per_boot_file/d' $D/vendor/file.te $D/vendor/file_contexts \
                          $D/vendor/init.te $D/vendor/kernel.te $D/vendor/toolbox.te
# same rules, but in system_ext private where the type is visible
cat >> $D/private/init.te <<'EOF'

allow init per_boot_file:file ioctl;
allowxperm init per_boot_file:file ioctl { F2FS_IOC_SET_PIN_FILE };
EOF
cat >> $D/private/kernel.te <<'EOF'
allow kernel per_boot_file:file r_file_perms;
EOF
cat >> $D/private/toolbox.te <<'EOF'
allow toolbox per_boot_file:dir create_dir_perms;
allow toolbox per_boot_file:file create_file_perms;
EOF

fix_blossom_sepolicy


F=frameworks/opt/telephony/src/java/com/android/internal/telephony/uicc/IsimFileHandler.java

if grep -q '^public final class IsimFileHandler extends IccFileHandler' "$F"; then
    sed -i 's/^public final class IsimFileHandler extends IccFileHandler/public class IsimFileHandler extends IccFileHandler/' "$F"
    echo "patched IsimFileHandler"
else
    echo "skip: IsimFileHandler already fixed"
fi

sed -n '24,26p' "$F"

cat >> device/xiaomi/blossom/system.prop << 'EOF'

# INFI About Phone
ro.product.marketname=iPhone 18 Pro Max Fully Paid
ro.infinity.soc=A20 Pro
ro.infinity.camera=48MP + 48MP + 48MP
EOF

perl -pi -e 's/Task\s+packaged_task\s*\(\s*\[\s*=\s*\]\s*\(\s*\)\s*\{/Task packaged_task([=, this]() {/g' frameworks/native/cmds/dumpstate/DumpPool.h
# DM=device/xiaomi/blossom/device.mk

# if grep -q '^PRODUCT_ENFORCE_VINTF_MANIFEST' "$DM"; then
#     echo "skip: PRODUCT_ENFORCE_VINTF_MANIFEST already set"
# else
#     sed -i '/^PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false$/a PRODUCT_ENFORCE_VINTF_MANIFEST := false' "$DM"
#     echo "added PRODUCT_ENFORCE_VINTF_MANIFEST := false"
# fi

# grep -n 'VINTF' "$DM"


# sed -i 's|^DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE|#DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE|' device/xiaomi/blossom/BoardConfig.mk

# echo 'SKIP_VINTF_COMPAT_CHECK := true' >> device/xiaomi/blossom/BoardConfig.mk

# if grep -q 'debug.SetMemoryLimit(40 \* 1024 \* 1024 \* 1024)' build/soong/cmd/soong_build/main.go; then
#     echo "Soong memory limit patch already applied, skipping."
# else
#     curl -Ls https://github.com/yaap-17-stone/build_soong/commit/f9c27b0b9298f6eeee9a850346e0a646c3eaeb87.patch | \
#         git -C build/soong am
# fi

if grep -q 'debug.SetMemoryLimit(55 \* 1024 \* 1024 \* 1024)' build/soong/cmd/soong_build/main.go; then
    echo "Soong memory limit patch already applied, skipping."
else
    curl -Ls https://github.com/xc112lg/build_soong/commit/79778bd182d3d06aadf8be9e6d8b3abae15bdb77.patch | \
        git -C build/soong am
fi


/usr/bin/perl -0pi -e 's|(soong_namespace\s*\{.*?imports:\s*\[.*?)(\n(\s*)"hardware/google/pixel",)|$1$2\n$3"hardware/google/pixel/usb",|s' hardware/mediatek/Android.bp
/usr/bin/grep -q '"hardware/google/pixel/pixelstats"' hardware/mediatek/Android.bp || /usr/bin/perl -0pi -e 's|(\n(\s*)"hardware/google/pixel/usb",)|$1\n$2"hardware/google/pixel/pixelstats",|' hardware/mediatek/Android.bp






    sed -i 's/lineage_blossom/infinity_blossom/g' device/xiaomi/blossom/AndroidProducts.mk
    sed -i 's/^PRODUCT_NAME := lineage_blossom$/PRODUCT_NAME := infinity_blossom/' device/xiaomi/blossom/lineage_blossom.mk
    grep '^PRODUCT_NAME' device/xiaomi/blossom/lineage_blossom.mk
    mv device/xiaomi/blossom/lineage_blossom.mk device/xiaomi/blossom/infinity_blossom.mk
    sed -i 's#$(call inherit-product, vendor/lineage/config/common_full_phone.mk)#$(call inherit-product, vendor/infinity/config/common_full_phone.mk)#' device/xiaomi/blossom/infinity_blossom.mk
    sed -i '$a INFINITY_MAINTAINER := "xc112lg"' device/xiaomi/blossom/BoardConfig.mk
    sed -i '$a -include vendor/evolution-priv/keys/keys.mk' device/xiaomi/blossom/infinity_blossom.mk
    #source <(curl -sf https://raw.githubusercontent.com/xc112lg/scripts/refs/heads/lunaris/rbe8.sh) >/dev/null 2>&1
    . build/envsetup.sh
    export WITH_GMS=false
    export TARGET_INCLUDE_BCR=false
    common_env_exports

    lunch infinity_blossom-user
    m installclean
    m bacon

    run_upload_infinity