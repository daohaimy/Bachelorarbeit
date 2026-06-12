#pragma once
#ifdef __cplusplus
extern "C" {
#endif

void ak_free(char* ptr);

char* ak_toggle_mic_json(const char* inputJson);
char* ak_stop_stt_json(void);
char* ak_speak_json(const char* inputJson);
char* ak_stop_speak_json(void);
char* ak_get_state_json(void);
char* ak_request_permissions_json(void);

#ifdef __cplusplus
}
#endif
