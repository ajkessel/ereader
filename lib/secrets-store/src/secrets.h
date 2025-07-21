#ifndef SECRETS_H
#define SECRETS_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef BUILDING_DLL
    #define KOREADERSECRETS_API __declspec(dllexport)
  #else
    #define KOREADERSECRETS_API __declspec(dllimport)
  #endif
#else
  #if __GNUC__ >= 4
    #define KOREADERSECRETS_API __attribute__ ((visibility ("default")))
  #else
    #define KOREADERSECRETS_API
  #endif
#endif

KOREADERSECRETS_API const char *get_instapaper_consumer_key();
KOREADERSECRETS_API const char *get_instapaper_consumer_secret();

#ifdef __cplusplus
}
#endif

#endif // SECRETS_H 