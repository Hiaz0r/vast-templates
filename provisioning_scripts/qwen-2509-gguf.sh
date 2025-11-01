#!/bin/bash
# Provisioning: ComfyUI + Qwen-Image-Edit-2509 (GGUF) für 24GB-Instanz
# Option B: ComfyUI + GGUF (VRAM-freundlich)

# --- Basics & Paths ---
source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# --- Optional: Pakete / Nodes / Pip ---
APT_PACKAGES=(
    # "ffmpeg"
    # "git"
)

PIP_PACKAGES=(
    # zusätzliche Python-Pakete nach Bedarf
)

# GGUF-Unterstützung für ComfyUI
NODES=(
  "https://github.com/city96/ComfyUI-GGUF"
)

# (Optional) Workflows: Qwen-Image-Edit-Workflows als JSON eintragen
WORKFLOWS=(
  # "https://example.com/workflows/qwen_image_edit_2509_basic.json"
)

# --- Qwen Image Edit 2509 – Dateien (GGUF/Safetensors) ---
# UNet (GGUF) → ComfyUI/models/unet/
QWEN_GGUF_UNET=(
  "https://huggingface.co/QuantStack/Qwen-Image-Edit-2509-GGUF/resolve/main/Qwen-Image-Edit-2509-Q5_1.gguf?download=true"
)

# Lora → ComfyUI/models/loras/
QWEN_LORA=(
  "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Edit-2509/Qwen-Image-Edit-2509-Lightning-4steps-V1.0-bf16.safetensors"
)

# Text-Encoder (Qwen2.5-VL-7B, GGUF) → ComfyUI/models/text_encoders/
# (solide Qualität/Größe: Q5_K_M; du kannst hier auch Q6_K oder BF16 wählen)
QWEN_TEXT_ENCODERS=(
  "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q5_K_M.gguf?download=true"
)

# mmproj (BF16, GGUF) → gleiches Verzeichnis wie der Text-Encoder
QWEN_MMPROJ=(
  "https://huggingface.co/unsloth/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-BF16.gguf?download=true"
)

# VAE (safetensors) → ComfyUI/models/vae/
QWEN_VAE=(
  "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header

    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages

    # Workflows (optional)
    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"

    # Qwen 2509 Downloads
    provisioning_get_files "${COMFYUI_DIR}/models/unet" "${QWEN_GGUF_UNET[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${QWEN_LORA[@]}"    
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${QWEN_TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${QWEN_MMPROJ[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${QWEN_VAE[@]}"

    # mmproj passend zum Text-Encoder benennen (Loader-Erwartung)
    provisioning_align_mmproj_name

    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
        sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
        pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s file(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

# Benennt mmproj so um, dass der Prefix zum Text-Encoder passt
# Beispiel:
#  - Text-Encoder: Qwen2.5-VL-7B-Instruct-Q5_K_M.gguf
#  - mmproj:       Qwen2.5-VL-7B-Instruct-mmproj-BF16.gguf
# -> Loader findet die Datei zuverlässiger
function provisioning_align_mmproj_name() {
    local encdir="${COMFYUI_DIR}/models/text_encoders"
    shopt -s nullglob
    # nimm den ersten *.gguf als "Haupt"-Textencoder
    local te_file
    for f in "${encdir}/"*.gguf; do
        if [[ "$f" != *"mmproj"* ]]; then
            te_file="$(basename "$f")"
            break
        fi
    done
    # mmproj-Datei suchen
    local mm_file
    for f in "${encdir}/"*.gguf; do
        if [[ "$f" == *"mmproj"* ]]; then
            mm_file="$(basename "$f")"
            break
        fi
    done
    if [[ -n "$te_file" && -n "$mm_file" ]]; then
        local prefix="${te_file%.gguf}"
        local new_mm="${encdir}/${prefix/-Q*/}-mmproj-BF16.gguf"
        # Fallback: wenn obige Ersetzung nichts ändert, einfach TE-Prefix + "-mmproj-BF16.gguf"
        if [[ "$new_mm" == "${encdir}/${te_file%.gguf}-Q"* ]]; then
          new_mm="${encdir}/${te_file%.gguf}-mmproj-BF16.gguf"
        fi
        if [[ "${encdir}/${mm_file}" != "$new_mm" ]]; then
            mv -f "${encdir}/${mm_file}" "$new_mm"
            printf "Renamed mmproj to: %s\n" "$new_mm"
        fi
    fi
    shopt -u nullglob
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"
    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")
    [[ "$response" -eq 200 ]]
}

# Download from $1 URL to $2 dir
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi

    if [[ -n $auth_token ]]; then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
