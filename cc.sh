curl -sf https://raw.githubusercontent.com/xc112lg/blossom_releases/refs/heads/main/build1.sh | bash  -s alphadroid  2>&1 | tee build1.log && curl -F "file=@build1.log" https://temp.sh/upload

#curl -sf https://raw.githubusercontent.com/xc112lg/blossom_releases/refs/heads/main/bb.sh | bash
