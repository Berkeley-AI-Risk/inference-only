# Fixed input staging for the Qwen CL. No vendor/source encryption is needed
# for this local build; AMD/AWS protected IP remains in the installed HDK.
if {$ENCRYPT} {error "Use --no-encrypt for this reproducible candidate build"}
foreach source [glob -directory ${CL_DIR}/design *] {
    if {[file isfile $source]} {file copy -force $source $src_post_enc_dir}
}
# $readmemh uses the build working directory. ROMs are also added to sources_1.
foreach name {silu-bf16.hex softmax-exp2.hex model-page-roots.hex} {
    file copy -force ${CL_DIR}/design/rom/$name ${scripts_dir}/$name
}

