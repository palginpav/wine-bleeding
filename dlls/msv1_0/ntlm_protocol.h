/*
 * Native NTLM protocol implementation for Wine
 */

#ifndef __WINE_NTLM_PROTOCOL_H
#define __WINE_NTLM_PROTOCOL_H

#include <windef.h>

/* Generate NTLM Type1 (Negotiate) message */
int ntlm_generate_type1(unsigned int flags, unsigned char *output, int output_max);

/* Parse NTLM Type2 (Challenge) message */
int ntlm_parse_type2(const unsigned char *input, int input_len,
                     unsigned char *server_challenge,
                     unsigned int *flags,
                     unsigned char **target_info, int *target_info_len);

/* Generate NTLM Type3 (Authenticate) message */
int ntlm_generate_type3(const unsigned char *server_challenge,
                         unsigned int neg_flags,
                         const WCHAR *username, int username_len,
                         const WCHAR *domain, int domain_len,
                         const WCHAR *password, int password_len,
                         const WCHAR *workstation, int workstation_len,
                         const unsigned char *target_info, int target_info_len,
                         unsigned char *output, int output_max,
                         unsigned char *session_key);

#endif /* __WINE_NTLM_PROTOCOL_H */
