#!/bin/bash
# ==============================================================================
# blossom superscript — unified build + release dispatcher for Xiaomi "blossom"
#
# Usage:
#   ./build.sh lunaris     # or lineage / evolution
#   curl -sf <raw-url-to-this-file> | bash -s lunaris
#   curl -sf <raw-url-to-this-file> | bash -s -- lineage
#
# One script now does the whole pipeline per target (build → package → GitHub
# release → Telegram announce), merging what used to be build.sh + upload.sh
# (itself a merge of upevo.sh + multi_upload3.sh):
#   1. Build the ROM (Lunaris AOSP / LineageOS / Evolution X) for device "blossom"
#   2. Stage the resulting zip/img/tar into the blossom_release repo
#   3. Create/replace the GitHub release + tag and upload the artifacts
#   4. Send the Telegram announcement (Telegraph changelog + image fallback)
#
# All three ROMs release into ONE shared GitHub repo: blossom_release
# (must already exist on GitHub under xc112lg). Each ROM keeps its own
# release tag/version string (e.g. LunarisAOSP-20260712, lineage-23.2-...,
# EvolutionX-16.0-...) so releases never collide in the shared repo.
#
# Override the release repo without editing the script:
#   RELEASE_REPO=some_other_repo ./build.sh lunaris
# ==============================================================================
set -euo pipefail

TARGET="${1:-}"

usage() {
    echo "Usage: $0 <lunaris|lineage|evolution>"
    echo "   or: curl -sf <url> | bash -s <lunaris|lineage|evolution>"
    exit 1
}

[ -z "$TARGET" ] && usage

case "$TARGET" in
    lunaris|lineage|evolution) ;;
    *)
        echo "✗ Unknown target: '$TARGET'"
        usage
        ;;
esac

# ------------------------------------------------------------------------------
# Shared setup (identical across all three variants)
# ------------------------------------------------------------------------------
load_env() {
    if [ -f .env ]; then
        export $(cat .env | grep -v '#' | xargs)
        echo "✓ Loaded .env from current directory"
    elif [ -f ../.env ]; then
        export $(cat ../.env | grep -v '#' | xargs)
        echo "✓ Loaded .env from parent directory"
    else
        echo "⚠ .env file not found"
    fi
}

common_prep() {
    git config --global url."https://${GH_TOKEN}:x-oauth-basic@github.com/".insteadOf "https://github.com/"
    rm -rf .repo/local_manifests/
    rm -rf device/xiaomi
    rm -rf kernel/xiaomi/blossom
    rm -rf TMP_PATCHES
    sudo apt update >/dev/null 2>&1
    sudo apt install patchelf -y >/dev/null 2>&1
}

common_env_exports() {
    export TARGET_USES_PICO_GAPPS=true
    export TARGET_INCLUDE_VIA=true
    export TARGET_INCLUDE_REVAMPED=true
    export SELINUX_IGNORE_NEVERALLOWS=true
    sed -i '$a -include vendor/evolution-priv/keys/keys.mk' device/xiaomi/blossom/lineage_blossom.mk
}

# ------------------------------------------------------------------------------
# Variant: Evolution X
# ------------------------------------------------------------------------------
run_evolution() {
    common_prep
    rm -rf .repo/local_manifests packages/apps/Evolver vendor/extras
    repo init -u https://github.com/Evolution-X/manifest -b bka --git-lfs --depth=1
    git clone https://$GH_TOKEN@github.com/xc112lg/blossom_manifest.git -b main .repo/local_manifests
    repo sync -c -j32 --force-sync --no-clone-bundle --no-tags
    /opt/crave/resync.sh
    rm -rf hardware/lineage/interfaces/sensors
    source <(curl -sf https://raw.githubusercontent.com/xc112lg/scripts/refs/heads/lunaris/rbe8.sh) >/dev/null 2>&1
    . build/envsetup.sh
    export WITH_GMS=false
    export TARGET_INCLUDE_BCR=false
    common_env_exports
    sed -i '\|vendor/extras/prebuilt/product/fonts,\$(TARGET_COPY_OUT_PRODUCT)/fonts|d' vendor/extras/evolution.mk
    sed -i '/<string-array name="emoji_style_entries">/,/<\/string-array>/{/emoji_style_stock/!{/<item>/d}}' packages/apps/Evolver/res/values/evolution_arrays.xml
    sed -i '/<string-array name="emoji_style_values">/,/<\/string-array>/{/<item>android<\/item>/!{/<item>/d}}' packages/apps/Evolver/res/values/evolution_arrays.xml
    sed -i '/fonts_customization_emoji_\(ios\|samsung\|swiftui\|facebook\)\.xml/d' vendor/extras/evolution.mk

    lunch lineage_blossom-bp4a-user
    m installclean
    m evolution

    run_upload_evolution
}

# ------------------------------------------------------------------------------
# Variant: LineageOS
# ------------------------------------------------------------------------------
run_lineage() {
    common_prep
    rm -rf vendor/lineage
    rm -rf hardware/mediatek
    rm -rf .repo/local_manifests
    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs --depth=1
    git clone https://$GH_TOKEN@github.com//xc112lg/blossom_manifest.git -b a1 .repo/local_manifests
    repo sync -c -j32 --force-sync --no-clone-bundle --no-tags
    /opt/crave/resync.sh
    source <(curl -sf https://raw.githubusercontent.com/xc112lg/scripts/refs/heads/lunaris/rbe8.sh) >/dev/null 2>&1
    . build/envsetup.sh

    curl -L https://github.com/xc112lg/android_hardware_mediatek/commit/b8a9f24f9ff6e8de021fa33fc65520571fcf7478.patch | git -C hardware/mediatek am
    curl -L https://github.com/xc112lg/android_hardware_mediatek/commit/8c779b742a41bfd89376933722c5232ba7b1731f.patch | git -C hardware/mediatek am

    export WITH_SU=true
    export WITH_GMS=false
    export EVO_BUILD_TYPE=Unofficial

    sed -i 's|tar xfp $PARAM_BOOTANIMATION_TAR -C $INTERMEDIATES|python3 -c "import tarfile; tarfile.open(\\"$PARAM_BOOTANIMATION_TAR\\").extractall(path=\\"$INTERMEDIATES\\")"|' vendor/lineage/bootanimation/gen-bootanimation.sh
    sed -i '/Command:.*buildFlagInternal/c\            Command: `${buildFlagInternal} --maps-file ${in} --quiet --declarations-only get && : > ${out}`,' build/soong/aconfig/build_flags/init.go
    sed -i '/^import subprocess$/a from datetime import datetime, timezone' build/soong/scripts/gen_build_prop.py && sed -i '/config\["Date"\] = subprocess.check_output/,/config\["DateUtc"\] = subprocess.check_output/c\  dt = datetime.fromtimestamp(int(raw_date), timezone.utc)\n  config["Date"] = dt.strftime("%a %b %d %H:%M:%S UTC %Y")\n  config["DateUtc"] = str(int(raw_date))' build/soong/scripts/gen_build_prop.py

    common_env_exports

    export RBE_LOG=DEBUG
    export RBE_VERBOSE=1

    lunch lineage_blossom-bp4a-user
    m installclean
    m bacon

    run_upload_lineage
}

# ------------------------------------------------------------------------------
# Variant: Lunaris AOSP
# ------------------------------------------------------------------------------
run_lunaris() {
    common_prep
    rm -rf .repo/local_manifests packages/apps/Evolver vendor/extras
    repo init -u https://github.com/Lunaris-AOSP/android -b 16.2 --git-lfs --depth=1
    git clone https://$GH_TOKEN@github.com/xc112lg/blossom_manifest.git -b main .repo/local_manifests
    repo sync -c -j32 --force-sync --no-clone-bundle --no-tags
    /opt/crave/resync.sh
    rm -rf hardware/lineage/interfaces/sensors
    source <(curl -sf https://raw.githubusercontent.com/xc112lg/scripts/refs/heads/lunaris/rbe8.sh) >/dev/null 2>&1
    . build/envsetup.sh
    export WITH_GMS=false
    export TARGET_INCLUDE_BCR=false
    export ro.lunaris.maintainer=xc112lg
    common_env_exports
    sed -i "\$a ro.lunaris.maintainer=xc112lg | How's Your Day" device/xiaomi/blossom/system.prop

    lunch lineage_blossom-bp4a-user
    m installclean
    m bacon

    run_upload_lunaris
}


# ------------------------------------------------------------------------------
# Stage 1 (equivalent of upevo.sh): clone the target repo and copy build output
# into it. Sets STAGE_DIR to the directory to cd into for stage 2.
# ------------------------------------------------------------------------------
stage_artifacts() {
    local repo="${RELEASE_REPO:-blossom_release}"

    if ! ls out/target/product/*/*.zip >/dev/null 2>&1; then
        echo "✗ No built zip found under out/target/product/*/ — did the build succeed?"
        exit 1
    fi

    rm -rf "$repo"
    git clone "https://${GH_TOKEN}@github.com//xc112lg/${repo}"

    cp out/target/product/*/*.zip "$repo/"
    cp out/target/product/*/*.tar "$repo/" 2>/dev/null || true

    cd "$repo"

    # lineage's upevo.sh drops the stock recovery/OTA package before uploading
    if [ "$TARGET" = "lineage" ]; then
        rm -f *-ota.zip
    fi
}

# ------------------------------------------------------------------------------
# Stage 2 (equivalent of multi_upload3.sh): GitHub release + Telegram notify.
# Variant-specific bits (version string, repo name, message body, banner) are
# injected as arguments/env from each run_upload_* function below.
# ------------------------------------------------------------------------------
release_and_notify() {
    local version_default="$1"
    local github_repo_default="$2"
    local telegram_message="$3"
    local banner_image="$4"

    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8

    if ! command -v gh &> /dev/null; then
        echo "GitHub CLI 'gh' not found. Downloading and installing..."
        wget https://github.com/cli/cli/releases/download/v2.40.1/gh_2.40.1_linux_amd64.tar.gz
        tar -xvf gh_2.40.1_linux_amd64.tar.gz
        sudo mv gh_*_linux_amd64/bin/gh /usr/local/bin/
        echo "GitHub CLI 'gh' installed successfully."
    else
        echo "GitHub CLI 'gh' is already installed."
    fi

    if ! gh auth status &> /dev/null; then
        gh auth login --with-token "$GH_TOKEN"
    else
        echo "Already authenticated with GitHub."
    fi

    local version="${custom_version:-$version_default}"

    if gh release view "$version" &> /dev/null; then
        echo "Deleting existing tag and releases for $version..."
        gh release delete "$version" --yes
        git tag -d "$version"
        git push origin --delete "$version"
        echo "Existing tag and releases deleted."
    fi

    git tag -a "$version" -m "Release $version"
    git push origin "$version" --force

    declare -a filenames
    filenames=(*.zip *.img *.txt *.json)

    if ! gh release create "$version" --title "Release $version" --notes "Release notes"; then
        echo "Error: Failed to create the release."
        exit 1
    fi

    for filename in "${filenames[@]}"; do
        gh release upload "$version" "$filename" --clobber
    done

    echo "Files uploaded successfully."

    # ============================================
    # TELEGRAM NOTIFICATION
    # ============================================
    echo "Preparing to send Telegram notification..."

    local RELEASE_TAG="$version"
    local GITHUB_REPO="${GITHUB_REPO:-$github_repo_default}"

    declare -a FILE_ENTRIES
    for filename in "${filenames[@]}"; do
        if [ -f "$filename" ]; then
            local download_url="https://github.com/$GITHUB_OWNER/$GITHUB_REPO/releases/download/$RELEASE_TAG/$filename"
            local file_size
            file_size=$(du -h "$filename" 2>/dev/null | cut -f1)
            FILE_ENTRIES+=("${filename}|${download_url}|${file_size}")
        fi
    done

    local CHANGELOG_URL="https://t.me/ProjectInfinityX/1882"

    if [ -n "${TELEGRAPH_TOKEN:-}" ]; then
        local CHANGELOG_CONTENT
        CHANGELOG_CONTENT=$(curl -fsSL \
            "https://raw.githubusercontent.com/Evolution-X/changelog/refs/heads/bka/changelogs/LATEST.txt" 2>/dev/null)

        if [ -n "$CHANGELOG_CONTENT" ]; then
            local TELEGRAPH_RESPONSE
            TELEGRAPH_RESPONSE=$(curl -s \
                -X POST "https://api.telegra.ph/createPage" \
                -d "access_token=$TELEGRAPH_TOKEN" \
                --data-urlencode "title=Changelog $(date '+%Y-%m-%d')" \
                --data-urlencode "author_name=xc112lg" \
                --data-urlencode "content=[{\"tag\":\"pre\",\"children\":[$(jq -Rs . <<< "$CHANGELOG_CONTENT")]}]")

            CHANGELOG_URL=$(echo "$TELEGRAPH_RESPONSE" | jq -r '.result.url // empty')
            if [ -n "$CHANGELOG_URL" ]; then
                echo "✓ Changelog uploaded: $CHANGELOG_URL"
            else
                CHANGELOG_URL="https://t.me/ProjectInfinityX/1882"
                echo "⚠ Failed to create Telegraph page"
            fi
        fi
    fi

    local DOWNLOADS_SECTION="
<b>📥 Downloads:</b>"

    for file_entry in "${FILE_ENTRIES[@]}"; do
        local filename="${file_entry%%|*}"
        local remaining="${file_entry#*|}"
        local url="${remaining%%|*}"
        local size="${remaining##*|}"

        local label="File"
        local download_links=""

        if [[ "$filename" == *"Vanilla"* ]] || [[ "$filename" == *"vanilla"* ]]; then
            label="📱 Vanilla ROM"
            download_links="<a href=\"${url}\">GitHub</a>"
        elif [[ "$filename" == *"GApps"* ]] || [[ "$filename" == *"gapps"* ]]; then
            label="🎯 GApps Package"
            download_links="<a href=\"${url}\">GitHub</a> | <a href=\"https://sourceforge.net/projects/nikgapps/files/Releases/Android-16/\">SourceForge</a>"
        elif [[ "$filename" == *"recovery"* ]] || [[ "$filename" == *"Recovery"* ]]; then
            label="🔧 Recovery Image"
            download_links="<a href=\"${url}\">Download</a>"
        elif [[ "$filename" == *.zip ]]; then
            label="📦 ROM Package"
            download_links="<a href=\"${url}\">Download</a>"
        elif [[ "$filename" == *.img ]]; then
            label="💾 Image File"
            download_links="<a href=\"${url}\">Download</a>"
        fi

        DOWNLOADS_SECTION+="
🔹 ${label} - ${download_links} (${size})"
        DOWNLOADS_SECTION+="
🔹 🎯 GApps Package <a href=\"https://sourceforge.net/projects/nikgapps/files/Releases/Android-16/\">SourceForge</a>"
    done

    DOWNLOADS_SECTION+="


<b>📲 <a href=\"https://telegra.ph/flashing-instruction-11-15\">Installation Guide</a></b>"

    # Substitute placeholders now that CHANGELOG_URL/DOWNLOADS_SECTION are known
    telegram_message="${telegram_message//\{\{CHANGELOG_URL\}\}/$CHANGELOG_URL}"
    telegram_message="${telegram_message//\{\{DOWNLOADS_SECTION\}\}/$DOWNLOADS_SECTION}"
    telegram_message="${telegram_message//\{\{BUILD_DATE\}\}/$(date '+%d/%m/%y')}"

    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
        echo "⚠ Telegram credentials not set. Skipping Telegram notification."
    else
        echo "Sending Telegram notification..."

        local MSG_LENGTH=${#telegram_message}
        echo "Message length: $MSG_LENGTH characters"
        local CAPTION_LIMIT=3500
        local FALLBACK=0

        if [ $MSG_LENGTH -le $CAPTION_LIMIT ]; then
            echo "✓ Message fits in caption - sending merged (image + text in one)"
            local TEMP_JSON
            TEMP_JSON=$(mktemp)
            cat > "$TEMP_JSON" << JSONEOF
{
    "chat_id": $TELEGRAM_CHAT_ID,
    "photo": "$banner_image",
    "caption": $(printf '%s\n' "$telegram_message" | jq -R -s .),
    "parse_mode": "HTML"
}
JSONEOF
            local RESPONSE
            RESPONSE=$(curl -s -X POST \
                -H "Content-Type: application/json" \
                -d @"$TEMP_JSON" \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendPhoto")
            rm -f "$TEMP_JSON"

            if echo "$RESPONSE" | grep -q '"ok":true'; then
                echo "✓ Telegram notification sent successfully (merged)!"
            else
                echo "⚠ Merged send failed, trying fallback..."
                FALLBACK=1
            fi
        else
            echo "⚠ Message too long for caption ($MSG_LENGTH > $CAPTION_LIMIT)"
            echo "✓ Using fallback: Sending image + text as separate messages"
            FALLBACK=1
        fi

        if [ "$FALLBACK" == "1" ]; then
            echo "Sending image first..."
            curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "{\"chat_id\": $TELEGRAM_CHAT_ID, \"photo\": \"$banner_image\", \"parse_mode\": \"HTML\"}" \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendPhoto" > /dev/null

            echo "Sending full message..."
            local TEMP_JSON
            TEMP_JSON=$(mktemp)
            cat > "$TEMP_JSON" << JSONEOF
{
    "chat_id": $TELEGRAM_CHAT_ID,
    "text": $(printf '%s\n' "$telegram_message" | jq -R -s .),
    "parse_mode": "HTML"
}
JSONEOF
            local RESPONSE
            RESPONSE=$(curl -s -X POST \
                -H "Content-Type: application/json" \
                -d @"$TEMP_JSON" \
                "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage")
            rm -f "$TEMP_JSON"

            if echo "$RESPONSE" | grep -q '"ok":true'; then
                echo "✓ Telegram notification sent successfully (fallback)!"
            else
                echo "✗ Failed to send Telegram notification"
                echo "Response: $RESPONSE"
            fi
        fi
    fi

    echo "✓ Release complete!"
}

# ------------------------------------------------------------------------------
# Variant configs
# ------------------------------------------------------------------------------
run_upload_evolution() {
    stage_artifacts
    local message="<b>EvolutionX-16.0 | UNOFFICIAL📱</b>

<b>Device:</b>Blossom
<b>👨‍💻 Builder:</b> <a href=\"http://t.me/xc112lg\">xc112lg</a>
<b>🤖 Android Version:</b> 16 | QPR2
<b>📅 Build Date:</b> {{BUILD_DATE}}
<b>⚙️ <a href=\"{{CHANGELOG_URL}}\">Changelog</a></b>
<b>📸 <a href=\"https://t.me/xc112lgblossomsc\">Screenshots</a></b>

{{DOWNLOADS_SECTION}}

<b>🐞 Issues:</b>
NFC not working

<b>🐞 Fixes:</b>
NFC wont spawn on non NFC variant
Remove font showing up on setting

<b>📝 Notes:</b>
Deleted additional fonts to save more space
Debloated
Reintroduce Sandbox cause someone need to hide apps from wife
Work with both core and basic gapps
Signed
Includes MIUI Camera,Lunari Dolby
July security patch
Default Kernel Sashimi

<b>❤️ Credits & Thanks:</b>
@HaiKitoo and 0kaarun for trees
zyexro for kernel
@Yohanyuan for audio fix
@astechpro20 for msg template
Yui Onanii, fukiame, @snnbyyds, <a href=\"http://t.me/Sushrut1101\">Sushrut</a>, xiaomi-blossom-dev contributors for base tree
Thanks to <a href=\"http://foss.crave.io\">crave.io</a> for server
0kaarun & Yohan Yuan for their help
Thanks to all other devs

<b>🌐 Stay Updated:</b>
📢 @xc112lgblossomupdate
📢 @xc112lgblossomupdate1

#blossom #UNOFFICIAL #Evolution-X #lunaridolby #Rom"

    release_and_notify \
        "EvolutionX-16.0-$(date '+%Y%m%d')" \
        "blossom_release" \
        "$message" \
        "https://github.com/Evolution-X/manifest/raw/bka/Banner.png"
}

run_upload_lineage() {
    stage_artifacts
    local message="<b>Lineage-23.2 | UNOFFICIAL📱</b>

<b>Device:</b>Blossom
<b>👨‍💻 Builder:</b> <a href=\"http://t.me/xc112lg\">xc112lg</a>
<b>🤖 Android Version:</b> 16 | QPR2
<b>📅 Build Date:</b> {{BUILD_DATE}}
<b>⚙️ <a href=\"{{CHANGELOG_URL}}\">Changelog</a></b>
<b>📸 <a href=\"https://t.me/xc112lgblossomsc\">Screenshots</a></b>

{{DOWNLOADS_SECTION}}

<b>🐞 Issues:</b>
NFC not working
Cant change to stock kernel

<b>🐞 Fixes:</b>
NFC wont spawn on non NFC variant

<b>📝 Notes:</b>
Debloated
Work with both core and basic gapps
Signed
Includes MIUI Camera,Lunari Dolby
July security patch
Default Kernel Sashimi

<b>❤️ Credits & Thanks:</b>
@HaiKitoo and 0kaarun for trees
zyexro for kernel
@Yohanyuan for audio fix
@astechpro20 for msg template
Yui Onanii, fukiame, @snnbyyds, <a href=\"http://t.me/Sushrut1101\">Sushrut</a>, xiaomi-blossom-dev contributors for base tree
Thanks to <a href=\"http://foss.crave.io\">crave.io</a> for server
0kaarun & Yohan Yuan for their help
Thanks to all other devs

<b>🌐 Stay Updated:</b>
📢 @xc112lgblossomupdate
📢 @xc112lgblossomupdate1

#blossom #UNOFFICIAL #lineage-23.2 #lunaridolby #Rom"

    release_and_notify \
        "lineage-23.2-$(date '+%Y%m%d')" \
        "blossom_release" \
        "$message" \
        "https://upload.wikimedia.org/wikipedia/commons/a/a3/Lineageos_logo.png"
}

run_upload_lunaris() {
    stage_artifacts
    local message="<b>LunarisAOSP 16.2 | UNOFFICIAL📱</b>

<b>Device:</b>Blossom
<b>👨‍💻 Builder:</b> <a href=\"http://t.me/xc112lg\">xc112lg</a>
<b>🤖 Android Version:</b> 16 | QPR2
<b>📅 Build Date:</b> {{BUILD_DATE}}
<b>⚙️ <a href=\"{{CHANGELOG_URL}}\">Changelog</a></b>
<b>📸 <a href=\"https://t.me/xc112lgblossomsc\">Screenshots</a></b>

{{DOWNLOADS_SECTION}}

<b>🐞 Issues:</b>
NFC not working

<b>🐞 Fixes:</b>
NFC wont spawn on non NFC variant
Remove font showing up on setting

<b>📝 Notes:</b>
Deleted additional fonts to save more space
Debloated
Reintroduce Sandbox cause someone need to hide apps from wife
Work with both core and basic gapps
Signed
Includes MIUI Camera,Lunari Dolby
July security patch
Default Kernel Sashimi

<b>❤️ Credits & Thanks:</b>
@HaiKitoo and 0kaarun for trees
zyexro for kernel
@Yohanyuan for audio fix
@astechpro20 for msg template
Yui Onanii, fukiame, @snnbyyds, <a href=\"http://t.me/Sushrut1101\">Sushrut</a>, xiaomi-blossom-dev contributors for base tree
Thanks to <a href=\"http://foss.crave.io\">crave.io</a> for server
0kaarun & Yohan Yuan for their help
Thanks to all other devs

<b>🌐 Stay Updated:</b>
📢 @xc112lgblossomupdate
📢 @xc112lgblossomupdate1

#blossom #UNOFFICIAL #LunarisAOSP #lunaridolby #Rom"

    release_and_notify \
        "LunarisAOSP-$(date '+%Y%m%d')" \
        "blossom_release" \
        "$message" \
        "https://avatars.githubusercontent.com/u/193316573?s=200&v=4"
}

# ------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------
load_env

echo "▶ Starting blossom build: $TARGET"
case "$TARGET" in
    evolution) run_evolution ;;
    lineage)   run_lineage ;;
    lunaris)   run_lunaris ;;
esac
echo "✓ Finished blossom build: $TARGET"
