/*
 * Tests for native NTLMv2 protocol implementation
 *
 * Copyright 2026 Wine Project
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#include <stdarg.h>
#include <windef.h>
#include <winbase.h>
#define SECURITY_WIN32
#include <sspi.h>
#include <ntsecapi.h>
#include "wine/test.h"

static void test_ntlm_acquire_credentials(void)
{
    SECURITY_STATUS status;
    CredHandle cred;
    TimeStamp expiry;

    status = AcquireCredentialsHandleW( NULL, (SEC_WCHAR *)L"NTLM", SECPKG_CRED_OUTBOUND,
                                         NULL, NULL, NULL, NULL, &cred, &expiry );
    ok( status == SEC_E_OK, "AcquireCredentialsHandle failed %#lx\n", status );
    if (status == SEC_E_OK)
        FreeCredentialsHandle( &cred );
}

static void test_ntlm_type1_generation(void)
{
    SECURITY_STATUS status;
    CredHandle cred;
    CtxtHandle ctx;
    TimeStamp expiry;
    SecBufferDesc out_desc;
    SecBuffer out_buf;
    ULONG attrs;

    status = AcquireCredentialsHandleW( NULL, (SEC_WCHAR *)L"NTLM", SECPKG_CRED_OUTBOUND,
                                         NULL, NULL, NULL, NULL, &cred, &expiry );
    if (status != SEC_E_OK)
    {
        skip( "Cannot acquire NTLM credentials: %#lx\n", status );
        return;
    }

    out_buf.BufferType = SECBUFFER_TOKEN;
    out_buf.cbBuffer = 2048;
    out_buf.pvBuffer = HeapAlloc( GetProcessHeap(), 0, 2048 );
    out_desc.ulVersion = SECBUFFER_VERSION;
    out_desc.cBuffers = 1;
    out_desc.pBuffers = &out_buf;

    status = InitializeSecurityContextW( &cred, NULL, (SEC_WCHAR *)L"test_target",
                                          ISC_REQ_CONFIDENTIALITY | ISC_REQ_CONNECTION,
                                          0, SECURITY_NATIVE_DREP, NULL, 0,
                                          &ctx, &out_desc, &attrs, &expiry );
    ok( status == SEC_I_CONTINUE_NEEDED || status == SEC_E_OK || status == SEC_E_NO_CREDENTIALS,
        "InitializeSecurityContext returned %#lx\n", status );

    if (status == SEC_I_CONTINUE_NEEDED)
    {
        /* Verify Type1 message structure */
        unsigned char *msg = out_buf.pvBuffer;
        ok( out_buf.cbBuffer >= 32, "Type1 message too short: %lu\n", out_buf.cbBuffer );
        ok( !memcmp( msg, "NTLMSSP\0", 8 ), "Wrong NTLM signature\n" );
        ok( msg[8] == 1 && msg[9] == 0 && msg[10] == 0 && msg[11] == 0,
            "Wrong message type: %02x %02x %02x %02x\n", msg[8], msg[9], msg[10], msg[11] );

        /* Flags should include NTLM, UNICODE */
        {
            unsigned int flags = msg[12] | (msg[13] << 8) | (msg[14] << 16) | (msg[15] << 24);
            ok( flags & 0x200, "NEGOTIATE_NTLM flag not set: %#x\n", flags );
            ok( flags & 0x01, "NEGOTIATE_UNICODE flag not set: %#x\n", flags );
        }

        DeleteSecurityContext( &ctx );
    }

    HeapFree( GetProcessHeap(), 0, out_buf.pvBuffer );
    FreeCredentialsHandle( &cred );
}

static void test_ntlm_type2_type3_exchange(void)
{
    SECURITY_STATUS status;
    CredHandle cred;
    CtxtHandle ctx;
    TimeStamp expiry;
    SecBufferDesc out_desc, in_desc;
    SecBuffer out_buf, in_buf;
    ULONG attrs;
    struct { unsigned short *User; unsigned long UserLength; unsigned short *Domain; unsigned long DomainLength; unsigned short *Password; unsigned long PasswordLength; unsigned long Flags; } identity;
    static const WCHAR userW[] = L"testuser";
    static const WCHAR domainW[] = L"TESTDOMAIN";
    static const WCHAR passwordW[] = L"testpassword";

    /* Use explicit credentials so we don't depend on cached creds */
    identity.User = (unsigned short *)userW;
    identity.UserLength = lstrlenW(userW);
    identity.Domain = (unsigned short *)domainW;
    identity.DomainLength = lstrlenW(domainW);
    identity.Password = (unsigned short *)passwordW;
    identity.PasswordLength = lstrlenW(passwordW);
    identity.Flags = 2;

    status = AcquireCredentialsHandleW( NULL, (SEC_WCHAR *)L"NTLM", SECPKG_CRED_OUTBOUND,
                                         NULL, &identity, NULL, NULL, &cred, &expiry );
    if (status != SEC_E_OK)
    {
        skip( "Cannot acquire NTLM credentials: %#lx\n", status );
        return;
    }

    /* Step 1: Generate Type1 */
    out_buf.BufferType = SECBUFFER_TOKEN;
    out_buf.cbBuffer = 2048;
    out_buf.pvBuffer = HeapAlloc( GetProcessHeap(), 0, 2048 );
    out_desc.ulVersion = SECBUFFER_VERSION;
    out_desc.cBuffers = 1;
    out_desc.pBuffers = &out_buf;

    status = InitializeSecurityContextW( &cred, NULL, (SEC_WCHAR *)L"test_target",
                                          ISC_REQ_CONNECTION, 0, SECURITY_NATIVE_DREP,
                                          NULL, 0, &ctx, &out_desc, &attrs, &expiry );
    ok( status == SEC_I_CONTINUE_NEEDED, "Type1 generation returned %#lx\n", status );

    if (status == SEC_I_CONTINUE_NEEDED)
    {
        /* Step 2: Construct a minimal Type2 challenge (simulated server response) */
        unsigned char type2[56];
        memset( type2, 0, sizeof(type2) );
        memcpy( type2, "NTLMSSP\0", 8 );
        type2[8] = 2; /* MessageType = 2 */
        /* TargetNameFields: empty */
        type2[12] = 0; type2[14] = 0; /* Len/MaxLen */
        type2[16] = 56; /* Offset */
        /* NegotiateFlags: NTLM | UNICODE */
        type2[20] = 0x33; type2[21] = 0x82; type2[22] = 0x8a; type2[23] = 0xe2;
        /* ServerChallenge: 8 bytes of test data */
        type2[24] = 0x01; type2[25] = 0x23; type2[26] = 0x45; type2[27] = 0x67;
        type2[28] = 0x89; type2[29] = 0xab; type2[30] = 0xcd; type2[31] = 0xef;

        in_buf.BufferType = SECBUFFER_TOKEN;
        in_buf.cbBuffer = sizeof(type2);
        in_buf.pvBuffer = type2;
        in_desc.ulVersion = SECBUFFER_VERSION;
        in_desc.cBuffers = 1;
        in_desc.pBuffers = &in_buf;

        out_buf.cbBuffer = 2048;
        memset( out_buf.pvBuffer, 0, 2048 );

        status = InitializeSecurityContextW( &cred, &ctx, (SEC_WCHAR *)L"test_target",
                                              ISC_REQ_CONNECTION, 0, SECURITY_NATIVE_DREP,
                                              &in_desc, 0, &ctx, &out_desc, &attrs, &expiry );
        ok( status == SEC_E_OK || status == SEC_I_CONTINUE_NEEDED,
            "Type3 generation returned %#lx\n", status );

        if (status == SEC_E_OK || status == SEC_I_CONTINUE_NEEDED)
        {
            /* Verify Type3 message */
            unsigned char *msg = out_buf.pvBuffer;
            ok( out_buf.cbBuffer >= 72, "Type3 message too short: %lu\n", out_buf.cbBuffer );
            ok( !memcmp( msg, "NTLMSSP\0", 8 ), "Wrong NTLM signature in Type3\n" );
            ok( msg[8] == 3 && msg[9] == 0 && msg[10] == 0 && msg[11] == 0,
                "Wrong message type: %02x %02x %02x %02x\n", msg[8], msg[9], msg[10], msg[11] );
        }

        DeleteSecurityContext( &ctx );
    }

    HeapFree( GetProcessHeap(), 0, out_buf.pvBuffer );
    FreeCredentialsHandle( &cred );
}

START_TEST(ntlm)
{
    test_ntlm_acquire_credentials();
    test_ntlm_type1_generation();
    test_ntlm_type2_type3_exchange();
}
