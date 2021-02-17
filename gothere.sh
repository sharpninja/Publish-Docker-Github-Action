#!/bin/sh
#set -e
echo "::debug::Start."

main() {
    echo "::debug::Main." # see https://github.com/actions/toolkit/issues/168

    if usesBoolean "${ACTIONS_STEP_DEBUG}"; then
        echo "::debug::ACTIONS_STEP_DEBUG: $ACTIONS_STEP_DEBUG"
        #     echo "::add-mask::${INPUT_USERNAME}"
        #     echo "::add-mask::${INPUT_PASSWORD}"
        set -x
    fi
}

main

echo "::debug::Finished."
