# Fixed input staging for the Qwen CL. No vendor/source encryption is needed
# for this local build; AMD/AWS protected IP remains in the installed HDK.
if {$ENCRYPT} {error "Use --no-encrypt for this reproducible candidate build"}
foreach source [glob -directory ${CL_DIR}/design *] {
    if {[file isfile $source]} {file copy -force $source $src_post_enc_dir}
}
# $readmemh uses the build working directory. ROMs are also added to sources_1.
foreach name {silu-bf16.hex softmax-exp2.hex model-page-roots-bank-0.hex model-page-roots-bank-1.hex model-page-roots-bank-2.hex model-page-roots-bank-3.hex model-page-roots-bank-4.hex model-page-roots-bank-5.hex model-page-roots-bank-6.hex model-page-roots-bank-7.hex model-page-roots-bank-8.hex model-page-roots-bank-9.hex model-page-roots-bank-10.hex model-page-roots-bank-11.hex model-page-roots-bank-12.hex model-page-roots-bank-13.hex model-page-roots-bank-14.hex model-page-roots-bank-15.hex model-page-roots-bank-16.hex model-page-roots-bank-17.hex model-page-roots-bank-18.hex model-page-roots-bank-19.hex model-page-roots-bank-20.hex model-page-roots-bank-21.hex model-page-roots-bank-22.hex model-page-roots-bank-23.hex model-page-roots-bank-24.hex model-page-roots-bank-25.hex model-page-roots-bank-26.hex model-page-roots-bank-27.hex model-page-roots-bank-28.hex model-page-roots-bank-29.hex model-page-roots-bank-30.hex model-page-roots-bank-31.hex model-page-roots-bank-32.hex} {
    file copy -force ${CL_DIR}/design/rom/$name ${scripts_dir}/$name
}

