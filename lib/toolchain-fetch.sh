#!/usr/bin/env sh

set -euo pipefail

version=$1

if [ -z "$version" ]; then
	echo "Must supply a version"
	version=1.11.6
fi

# Replace `.` by ` `, split into array
pins=( ${version//./ } )
v_major=${pins[0]}
v_minor=${pins[1]}
v_patch=${pins[2]}

declare -A targets=(
	[x86_64-linux]=https://julialang-s3.julialang.org/bin/linux/x64/$v_major.$v_minor/julia-$version-linux-x86_64.tar.gz
	[aarch64-linux]=https://julialang-s3.julialang.org/bin/linux/aarch64/$v_major.$v_minor/julia-$version-linux-aarch64.tar.gz
	[x86_64-darwin]=https://julialang-s3.julialang.org/bin/mac/x64/$v_major.$v_minor/julia-$version-mac64.tar.gz
	[aarch64-darwin]=https://julialang-s3.julialang.org/bin/mac/aarch64/$v_major.$v_minor/julia-$version-macaarch64.tar.gz
)

printf "\"$version\" = {\n"
for target in "${!targets[@]}"; do
	url=${targets[$target]}
	prefetch=$(nix --extra-experimental-features nix-command store prefetch-file --unpack --json --hash-type sha256 $url)
	hash=$(jq -r '.hash' <<< "$prefetch")
	printf "  $target = {\n"
	printf "    url = \"$url\";\n"
	printf "    hash = \"$hash\";\n"
	printf "  };\n"
done
printf "};\n"
