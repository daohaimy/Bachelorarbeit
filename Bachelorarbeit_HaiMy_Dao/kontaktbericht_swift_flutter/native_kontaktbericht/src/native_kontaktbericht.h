#ifndef NATIVE_KONTAKTBERICHT_H
#define NATIVE_KONTAKTBERICHT_H

#ifdef __cplusplus
extern "C" {
#endif

char* kb_extract_json(const char* inputJson);
char* kb_answer_followup_json(const char* inputJson);
char* kb_save_json(const char* inputJson);

char* kb_list_json(void);
char* kb_delete_json(const char* inputJson);

void  kb_free(char* ptr);

#ifdef __cplusplus
}
#endif

#endif
