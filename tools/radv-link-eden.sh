#!/usr/bin/env bash
# Source after setting root to the Eden port. Keep the qualified Eden heap;
# reuse the pinned RADV platform recipe for threads, libc, TLS and unwinding.
eden_radv_link_recipe() {
    local archive=$1
    local reference="$root/../mihawk-vulkan-review"
    local radv_sdk="$reference/.deps/native/ps5-payload-sdk"
    source "$reference/tools/radv-link.sh"
    radv_link_recipe "$reference" "$radv_sdk" "$archive" || return
    # The Eden linker already groups all native archives. lld rejects nested
    # groups, so flatten only the recipe's group delimiters.
    local input
    local inputs=()
    for input in "${radv_link_inputs[@]}"; do
        case "$input" in --start-group|--end-group) ;; *) inputs+=("$input") ;; esac
    done
    radv_link_inputs=("${inputs[@]}")
    local flag
    local retained=()
    for flag in "${radv_link_flags[@]}"; do
        case "$flag" in
            --wrap=malloc|--wrap=calloc|--wrap=realloc|--wrap=free|\
            --wrap=posix_memalign|--wrap=aligned_alloc|--wrap=memalign|\
            --wrap=malloc_usable_size|--wrap=reallocf|--wrap=reallocarray|\
            --wrap=getline|--wrap=getdelim) ;;
            *) retained+=("$flag") ;;
        esac
    done
    # The static Mesa ICD exports radv_GetInstanceProcAddr. Eden's existing
    # static loader uses the standard public name.
    radv_link_flags=("${retained[@]}" --defsym=vkGetInstanceProcAddr=radv_GetInstanceProcAddr
        --undefined=__real_fclose --undefined=__real_fflush)
    # Mesa generates its dispatch tables with weak references (--weak in
    # src/amd/vulkan/meson.build): entry points this build never implements
    # stay weak-undefined and the linker resolves them to 0. Those NULL slots
    # are correct at runtime — vk_*_dispatch_table_from_entrypoints skips NULL
    # entries and the common table fills only the slots the driver left NULL
    # (src/vulkan/util/vk_dispatch_table_gen.py, vk_instance.c:182-184) — but
    # the native converter only accepts SDK-stub imports and rejects any other
    # dynamic UND symbol. Bind the truly-undefined weak entry points to 0
    # here, the same pattern as the --defsym=__dlopen=0 weak hooks in
    # link-headless-native.sh, so the image carries NULL slots and no extra
    # dynamic imports. The list is derived from the archive at link time, so a
    # Mesa pin change cannot leave it stale. Namespaces are driver/layer
    # private (radv_/sqtt_/rra_/rmv_/ctx_roll_/utrace_/annotate_/threaded_)
    # plus Mesa's own common/WSI tables (vk_common_/wsi_); Eden defines none
    # of these original names (its copies are the eden_radv_private_* renames),
    # so no strong definition can collide — a future collision would fail fast
    # at link time as a duplicate definition.
    local weak_undefined
    weak_undefined=$(nm -g --format=posix "$archive" 2>/dev/null | awk '
        $2 == "w" || $2 == "v" { weak[$1] = 1; next }
        $2 != "U" { defined[$1] = 1; next }
        END {
            for (s in weak)
                if (!(s in defined) &&
                    s ~ /^(radv_|sqtt_|rra_|rmv_|ctx_roll_|utrace_|annotate_|threaded_|vk_common_|wsi_)/ &&
                    s ~ /^[A-Za-z_][A-Za-z0-9_]*$/)
                    print s
        }' | sort) || return
    [[ -n $weak_undefined ]] || { echo "no weak-undefined RADV entry points found in $archive" >&2; return 1; }
    local weak_name
    while IFS= read -r weak_name; do
        [[ -n $weak_name ]] || continue
        radv_link_flags+=("--defsym=$weak_name=0")
    done <<< "$weak_undefined"
}
