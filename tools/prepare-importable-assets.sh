#!/usr/bin/env bash

set -euo pipefail

readonly TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly GLTF_TRANSFORM_VERSION="4.4.2"

model_paths=()
while IFS= read -r -d '' model_path; do
  model_paths+=("${model_path}")
done < <(
  find "${TEMPLATE_ROOT}/assets/models" -type f -name '*.glb' -print0 | sort -z
)

if [[ ${#model_paths[@]} -eq 0 ]]; then
  printf 'No GLB assets found under %s\n' "${TEMPLATE_ROOT}/assets/models" >&2
  exit 1
fi

for model_path in "${model_paths[@]}"; do
  model_tmp="$(mktemp "${TMPDIR:-/tmp}/summer-voxel-glb.XXXXXX.glb")"
  npx -y "@gltf-transform/cli@${GLTF_TRANSFORM_VERSION}" optimize \
    "${model_path}" \
    "${model_tmp}" \
    --compress false \
    --texture-compress webp \
    --texture-size 1024
  mv "${model_tmp}" "${model_path}"
done

# glTF Transform embeds the converted texture in each GLB, but its encoder can
# leave an unreferenced WebP scratch file beside the source model. The shipped
# Template keeps model textures self-contained, so remove those scratch files.
find "${TEMPLATE_ROOT}/assets/models" -type f -name '*.webp' -delete

printf 'Prepared %d GLB assets for the editor Template artifact.\n' \
  "${#model_paths[@]}"
