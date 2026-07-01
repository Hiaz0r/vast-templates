#!/bin/bash

# --- Basics & Paths ---
source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# --- Optional: Pakete / Nodes ---
APT_PACKAGES=(
    # "package-1"
    # "package-2"
)

PIP_PACKAGES=(
    # "package-1"
    # "package-2"
)

NODES=(    
    "https://github.com/nova452/ComfyUI-Conditioning-Rebalance.git"
)

# --- Workflows (leer oder eigene Krea2-Workflows eintragen) ---
WORKFLOWS=(
    # "https://example.com/your_krea2_workflow.json"
)

# --- Krea 2 Modelle (Turbo, FP8-scaled) ---
KREA2_TEXT_ENCODERS=(
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/text_encoders/qwen3vl_4b_fp8_scaled.safetensors"
)

KREA2_DIFFUSION_MODELS=(
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/diffusion_models/krea2_turbo_fp8_scaled.safetensors"
)

KREA2_VAE_MODELS=(
  "https://huggingface.co/Comfy-Org/Krea-2/resolve/main/vae/qwen_image_vae.safetensors"
)

KREA2_LORAS=(
  #"https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_coolblue.safetensors"
  #"https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_darkbrush.safetensors"
  #"https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_plasmoid.safetensors"
  #"https://huggingface.co/Comfy-Org/Krea-2/resolve/main/loras/krea2_warmpastel.safetensors"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header

    provisioning_update_comfyui
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages

    # Workflows (optional)
    workflows_dir="${COMFYUI_DIR}/user/default/workflows"
    mkdir -p "${workflows_dir}"
    provisioning_get_files "${workflows_dir}" "${WORKFLOWS[@]}"

    # Krea 2 Downloads
    provisioning_get_files "${COMFYUI_DIR}/models/text_encoders" "${KREA2_TEXT_ENCODERS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/diffusion_models" "${KREA2_DIFFUSION_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/vae" "${KREA2_VAE_MODELS[@]}"
    provisioning_get_files "${COMFYUI_DIR}/models/loras" "${KREA2_LORAS[@]}"

    provisioning_print_end
}

function provisioning_update_comfyui() {
    # Krea2-Architektur wird erst ab ComfyUI 0.26.0 erkannt (CLIPLoader type "krea2").
    # Stellt sicher, dass der Core aktuell ist, bevor die Modelle geladen werden.
    if [[ -d "${COMFYUI_DIR}/.git" ]]; then
        printf "Updating ComfyUI core for Krea2 support...\n"
        ( cd "${COMFYUI_DIR}" && git pull )
        if [[ -e "${COMFYUI_DIR}/requirements.txt" ]]; then
            pip install --no-cache-dir -r "${COMFYUI_DIR}/requirements.txt"
        fi
    else
        printf "WARNING: %s is not a git repo, could not auto-update. Verify ComfyUI >= 0.26.0 manually.\n" "${COMFYUI_DIR}"
    fi
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
