/* socklen_t_fallback.h — local ljh-sh patch for the broken
 * Xcode 15.4 SDK typedefs.
 *
 * Background: the new SDK's `<sys/_types/_*.h>` headers do:
 *   typedef __darwin_XXX_t YYY;
 * which expands to `typedef unsigned int YYY;` and is rejected
 * by clang 17+ with "type-name cannot be signed or unsigned".
 * The workaround is to pre-define the SDK's guard macros so
 * the typedefs are skipped, AND inject our own typedefs from
 * the inlined gnulib block before the system includes.
 *
 * The affected headers (as of macOS SDK 15.4):
 *   <sys/_types/_socklen_t.h>   _SOCKLEN_T
 *   <sys/_types/_ssize_t.h>     _SSIZE_T
 *   <sys/_types/_intmax_t.h>    _INTMAX_T
 *   <sys/_types/_uid_t.h>       _UID_T
 *   <sys/_types/_gid_t.h>       _GID_T
 *   <sys/_types/_off_t.h>       _OFF_T
 *   <sys/_types/_id_t.h>        _ID_T
 *   <sys/_types/_blkcnt_t.h>   _BLKCNT_T
 *   <sys/_types/_fsblkcnt_t.h> _FSBLKCNT_T
 *   <sys/_types/_fsfilcnt_t.h> _FSFILCNT_T
 *
 * Pass via CFLAGS:
 *   -D_SOCKLEN_T -D_SSIZE_T -D_INTTMAX_T -D_UID_T -D_GID_T \
 *   -D_OFF_T -D_ID_T -D_BLKCNT_T -D_FSBLKCNT_T -D_FSFI LCNT_T \
 *   -include <path-to-this-file>
 */
#ifndef _SOCKLEN_T_FALLBACK_LJHSH_DONE
#define _SOCKLEN_T_FALLBACK_LJHSH_DONE

#include <machine/types.h>
#ifndef socklen_t
typedef __darwin_socklen_t socklen_t;
#endif
#ifndef ssize_t
typedef __darwin_ssize_t ssize_t;
#endif
#ifndef intmax_t
typedef __darwin_intptr_t intmax_t;
#endif
#ifndef uid_t
typedef __uint32_t uid_t;
#endif
#ifndef gid_t
typedef __uint32_t gid_t;
#endif
#ifndef off_t
typedef __darwin_off_t off_t;
#endif

#endif
