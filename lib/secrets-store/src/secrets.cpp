#include "secrets.h"
#include "generated_secrets.h" // auto-generated at build time
#include "../obfuscate/obfuscate.h"

extern "C" {
const char *get_instapaper_consumer_key() {
    return AY_OBFUSCATE(INSTAPAPER_CONSUMER_KEY);
}

const char *get_instapaper_consumer_secret() {
    return AY_OBFUSCATE(INSTAPAPER_CONSUMER_SECRET);
}
} 