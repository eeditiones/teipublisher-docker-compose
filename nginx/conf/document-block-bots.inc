# Safe use of if: only `return`. Not used for markdown exports.
if ($is_llm_ua) {
    return 429;
}
