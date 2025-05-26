#!/bin/sh
set -u

write_result() {
  flock scryer_libs/temp/install_resp.pl.lock \
    -c "echo \"result(\\\"$1\\\", $2).\" >> scryer_libs/temp/install_resp.pl"
}

write_success() {
  write_result "$1" "success"
}

write_error() {
  escaped_error=$(printf '%s' "$2" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  escaped_error=$(printf '%s' "$escaped_error" | tr '\r\n' '\\n')
  escaped_error=$(printf '%s' "$escaped_error" | sed 's/ / /g')
  write_result "$1" "error(\\\"$escaped_error\\\")"
}


IFS='|' read -r -a DEPENDENCIES <<< "$DEPENDENCIES_STRING"

touch scryer_libs/temp/install_resp.pl

for dependency in "${DEPENDENCIES[@]}"; do
    unset dependency_term dependency_kind dependency_name git_url git_branch git_tag git_hash dependency_path
    
    IFS=';' read -ra fields <<< "$dependency"
    
    for field in "${fields[@]}"; do
        key=${field%%=*}
        value=${field#*=}

        case "$key" in
            dependency_term) dependency_term=$value ;;
            dependency_kind) dependency_kind=$value ;;
            dependency_name) dependency_name=$value ;;
            git_url) git_url=$value ;;
            git_branch) git_branch=$value ;;
            git_tag) git_tag=$value ;;
            git_hash) git_hash=$value ;;
            dependency_path) dependency_path=$value ;;
        esac
    done

    echo "Ensuring is installed: ${dependency_term}"

    case "${dependency_kind}" in
        git_default)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )

                if [ -z "$error_output" ]; then
                    write_success "${dependency_name}"
                else
                    write_error "${dependency_name}" "$error_output"
                fi
            ) &
            ;;
        git_branch)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    --branch "${git_branch}" \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )
                
                if [ -z "$error_output" ]; then
                    write_success "${dependency_name}"
                else
                    write_error "${dependency_name}" "$error_output"
                fi
            ) &
            ;;
        git_tag)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    --branch "${git_tag}" \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )
                
                if [ -z "$error_output" ]; then
                    write_success "${dependency_name}"
                else
                    write_error "${dependency_name}" "$error_output"
                fi
            ) &
            ;;
        git_hash)
            (
                error_output=$(git clone \
                    --quiet \
                    --depth 1 \
                    --single-branch \
                    "${git_url}" \
                    "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null
                )
                
                if [ -z "$error_output" ]; then
                    fetch_error=$(git -C "scryer_libs/packages/${dependency_name}" fetch \
                        --quiet \
                        --depth 1 \
                        origin "${git_hash}" 2>&1 1>/dev/null
                    )
                    switch_error=$(git -C "scryer_libs/packages/${dependency_name}" switch \
                        --quiet \
                        --detach \
                        "${git_hash}" 2>&1 1>/dev/null
                    )
                    combined_error="${fetch_error}; ${switch_error}"

                    if [ -z "$fetch_error" ] && [ -z "$switch_error" ]; then
                        write_success "${dependency_name}"
                    else
                        write_error "${dependency_name}" "$combined_error"
                    fi
                else
                    write_error "${dependency_name}" "$error_output"
                fi
            ) &
            ;;
        path)
            (
                if [ -d "${dependency_path}" ]; then
                    error_output=$(ln -rsf "${dependency_path}" "scryer_libs/packages/${dependency_name}" 2>&1 1>/dev/null)

                    if [ -z "$error_output" ]; then
                        write_success "${dependency_name}"
                    else
                        write_error "${dependency_name}" "$error_output"
                    fi
                else
                    write_error "${dependency_name}" "${dependency_path} does not exist"
                fi
            ) &
            ;;
        *)
            echo "Unknown dependency kind: ${dependency_kind}"
            write_error "${dependency_name}" "Unknown dependency kind: ${dependency_kind}"
            ;;
    esac
done

wait

rm -f scryer_libs/temp/install_resp.pl.lock
