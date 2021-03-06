/*
 * core/env.c
 *
 * Copyright 2016 CC-by-nc-sa bztsrc@github
 * https://creativecommons.org/licenses/by-nc-sa/4.0/
 *
 * You are free to:
 *
 * - Share — copy and redistribute the material in any medium or format
 * - Adapt — remix, transform, and build upon the material
 *     The licensor cannot revoke these freedoms as long as you follow
 *     the license terms.
 *
 * Under the following terms:
 *
 * - Attribution — You must give appropriate credit, provide a link to
 *     the license, and indicate if changes were made. You may do so in
 *     any reasonable manner, but not in any way that suggests the
 *     licensor endorses you or your use.
 * - NonCommercial — You may not use the material for commercial purposes.
 * - ShareAlike — If you remix, transform, or build upon the material,
 *     you must distribute your contributions under the same license as
 *     the original.
 *
 * @brief Core environment parser (see FS0:\BOOTBOOT\CONFIG)
 */

#include <sys/sysinfo.h>

/*** parsed values ***/
uint64_t __attribute__ ((section (".data"))) nrphymax;
uint64_t __attribute__ ((section (".data"))) nrmqmax;
uint64_t __attribute__ ((section (".data"))) nrirqmax;
uint64_t __attribute__ ((section (".data"))) nrsrvmax;
uint64_t __attribute__ ((section (".data"))) nrlogmax;
uint64_t __attribute__ ((section (".data"))) fps;
uint8_t __attribute__ ((section (".data"))) identity;
uint8_t __attribute__ ((section (".data"))) networking;
uint8_t __attribute__ ((section (".data"))) sound;
uint8_t __attribute__ ((section (".data"))) identity;

/*** for overriding default or autodetected values ***/
extern sysinfo_t sysinfostruc;
extern uint64_t ioapic_addr;

unsigned char *env_hex(unsigned char *s, uint64_t *v, uint64_t min, uint64_t max)
{
    if(*s=='0' && *(s+1)=='x')
        s+=2;
    do{
        *v <<= 4;
        if(*s>='0' && *s<='9')
            *v += (uint64_t)((unsigned char)(*s)-'0');
        else if(*s >= 'a' && *s <= 'f')
            *v += (uint64_t)((unsigned char)(*s)-'a'+10);
        else if(*s >= 'A' && *s <= 'F')
            *v += (uint64_t)((unsigned char)(*s)-'A'+10);
        s++;
    } while((*s>='0'&&*s<='9')||(*s>='a'&&*s<='f')||(*s>='A'&&*s<='F'));
    if(*v < min)
        *v = min;
    if(max!=0 && *v > max)
        *v = max;
    return s;
}

unsigned char *env_dec(unsigned char *s, uint64_t *v, uint64_t min, uint64_t max)
{
    if(*s=='0' && *(s+1)=='x')
        return env_hex(s+2, v, min, max);
    *v=0;
    do{
        *v *= 10;
        *v += (uint64_t)((unsigned char)(*s)-'0');
        s++;
    } while(*s>='0'&&*s<='9');
    if(*v < min)
        *v = min;
    if(max!=0 && *v > max)
        *v = max;
    return s;
}

unsigned char *env_boolt(unsigned char *s, uint8_t *v)
{
    *v = (*s=='1'||*s=='t'||*s=='T');
    return s+1;
}

unsigned char *env_boolf(unsigned char *s, uint8_t *v)
{
    *v = !(*s=='0'||*s=='f'||*s=='F');
    return s+1;
}

unsigned char *env_display(unsigned char *s)
{
    uint64_t tmp;
    if(*s>='0' && *s<='9') {
        s = env_dec(s, &tmp, 0, 3);
        sysinfostruc.display = (uint8_t)tmp;
        return s;
    }
    sysinfostruc.display = DSP_MONO_COLOR;
    // skip separators
    while(*s==' '||*s=='\t')
        s++;
    if(s[0]=='m' && s[1]=='c')  sysinfostruc.display = DSP_MONO_COLOR;
    if(s[0]=='M' && s[1]=='C')  sysinfostruc.display = DSP_MONO_COLOR;
    if(s[0]=='s' && s[1]=='m')  sysinfostruc.display = DSP_STEREO_MONO;
    if(s[0]=='S' && s[1]=='M')  sysinfostruc.display = DSP_STEREO_MONO;
    if(s[0]=='a' && s[1]=='n')  sysinfostruc.display = DSP_STEREO_MONO;  //anaglyph
    if(s[0]=='s' && s[1]=='c')  sysinfostruc.display = DSP_STEREO_COLOR;
    if(s[0]=='S' && s[1]=='C')  sysinfostruc.display = DSP_STEREO_COLOR;
    if(s[0]=='r' && s[1]=='e')  sysinfostruc.display = DSP_STEREO_COLOR; //real 3D
    while(*s!=0 && *s!='\n')
        s++;
    return s;
}

unsigned char *env_keymap(unsigned char *s)
{
    unsigned char *c = (unsigned char *)sysinfostruc.keymap;
    unsigned char *e = (unsigned char *)sysinfostruc.keymap + 7;

    while(c<e && s!=NULL && *s!=0) {
        *c = *s;
        c++;
        s++;
    }
    *c = 0;
    return s;
}

#if DEBUG
unsigned char *env_debug(unsigned char *s)
{
    uint64_t tmp;
    if(*s>='0' && *s<='9') {
        s = env_dec(s, &tmp, 0, 0xFFFF);
        sysinfostruc.debug = (uint16_t)tmp;
        return s;
    }
    sysinfostruc.debug = 0;
    while(*s!=0 && *s!='\n') {
        // skip separators
        if(*s==' '||*s=='\t'||*s==',')
            { s++; continue; }
        // terminators
        if(((s[0]=='f'||s[0]=='F')&&(s[1]=='a'||s[1]=='A')) ||
           ((s[0]=='n'||s[0]=='N')&&(s[1]=='o'||s[1]=='O'))) {
            sysinfostruc.debug = 0;
            break;
        }
        // debug flags
        if(s[0]=='m' && s[1]=='m')              sysinfostruc.debug |= DBG_MEMMAP;
        if(s[0]=='M' && s[1]=='M')              sysinfostruc.debug |= DBG_MEMMAP;
        if(s[0]=='t' && s[1]=='h')              sysinfostruc.debug |= DBG_THREADS;
        if(s[0]=='T' && s[1]=='H')              sysinfostruc.debug |= DBG_THREADS;
        if(s[0]=='e' && s[1]=='l')              sysinfostruc.debug |= DBG_ELF;
        if(s[0]=='E' && s[1]=='L')              sysinfostruc.debug |= DBG_ELF;
        if(s[0]=='r' && (s[1]=='i'||s[2]=='i')) sysinfostruc.debug |= DBG_RTIMPORT;
        if(s[0]=='R' && (s[1]=='I'||s[2]=='I')) sysinfostruc.debug |= DBG_RTIMPORT;
        if(s[0]=='r' && (s[1]=='e'||s[2]=='e')) sysinfostruc.debug |= DBG_RTEXPORT;
        if(s[0]=='R' && (s[1]=='E'||s[2]=='E')) sysinfostruc.debug |= DBG_RTEXPORT;
        if(s[0]=='i' && s[1]=='r')              sysinfostruc.debug |= DBG_IRQ;
        if(s[0]=='I' && s[1]=='R')              sysinfostruc.debug |= DBG_IRQ;
        if(s[0]=='d' && s[1]=='e')              sysinfostruc.debug |= DBG_DEVICES;
        if(s[0]=='D' && s[1]=='E')              sysinfostruc.debug |= DBG_DEVICES;
        if(s[0]=='s' && s[1]=='c')              sysinfostruc.debug |= DBG_SCHED;
        if(s[0]=='S' && s[1]=='C')              sysinfostruc.debug |= DBG_SCHED;
        if(s[0]=='m' && s[1]=='s')              sysinfostruc.debug |= DBG_MSG;
        if(s[0]=='M' && s[1]=='S')              sysinfostruc.debug |= DBG_MSG;
        if(s[0]=='l' && s[1]=='o')              sysinfostruc.debug |= DBG_LOG;
        if(s[0]=='L' && s[1]=='O')              sysinfostruc.debug |= DBG_LOG;
        s++;
    }
    return s;
}
#endif

/*** initialize environment ***/
void env_init()
{
    unsigned char *env = environment;
    unsigned char *env_end = environment+__PAGESIZE;
    uint64_t tmp;

    // set up defaults
    networking = sound = true;
    identity = false;
    sysinfostruc.systables[systable_hpet_ptr] =
        sysinfostruc.systables[systable_apic_ptr] =
            ioapic_addr = 0;
    nrirqmax = ISR_NUMHANDLER;
    nrphymax = nrlogmax = 8;
    nrmqmax = 1;
    fps = 10;
    sysinfostruc.nropenmax = 16;
    sysinfostruc.quantum = 1024;
    sysinfostruc.display = DSP_MONO_COLOR;
    sysinfostruc.debug = DBG_NONE;
    kmemcpy(&sysinfostruc.keymap, "en_us", 6);
    sysinfostruc.systables[systable_dsdt_ptr] = (uint64_t)fs_locate("etc/sys/dsdt");
    if(fs_size == 0)
        sysinfostruc.systables[systable_dsdt_ptr] = 0;

    // parse ascii text
    while(env < env_end && *env!=0) {
        // skip comments
        if((env[0]=='/'&&env[1]=='/') || env[0]=='#') {
            while(env[0]!=0 && env[0]!='\n')
                env++;
        }
        if(env[0]=='/'&&env[1]=='*') {
            env+=2;
            while(env[0]!=0 && env[-1]!='*' && env[0]!='/')
                env++;
        }
        // number of physical memory fragment pages
        if(!kmemcmp(env, "nrphymax=", 9)) {
            env += 9;
            env = env_dec(env, &nrphymax, 2, 128);
        } else
        // number of message queue pages
        if(!kmemcmp(env, "nrmqmax=", 8)) {
            env += 8;
            env = env_dec(env, &nrmqmax, 1, NRMQ_MAX);
        } else
        // maximum number of handlers per IRQ
        if(!kmemcmp(env, "nrirqmax=", 9)) {
            env += 9;
            env = env_dec(env, &nrirqmax, 4, 32);
        } else
        // number of services pages
        if(!kmemcmp(env, "nrsrvmax=", 9)) {
            env += 9;
            env = env_dec(env, &nrsrvmax, 1, NRSRV_MAX);
        } else
        // number of syslog buffer pages
        if(!kmemcmp(env, "nrlogmax=", 9)) {
            env += 9;
            env = env_dec(env, &nrlogmax, 4, 128);
        } else
        // number of file descriptors per thread. With fopen, number is unlimited.
        if(!kmemcmp(env, "nropenmax=", 10)) {
            env += 10;
            env = env_dec(env, &tmp, 4, 128);
            sysinfostruc.nropenmax = (uint8_t)tmp;
        } else
        // manually override HPET address
        if(!kmemcmp(env, "hpet=", 5)) {
            env += 5;
            // we only accept hex value for this parameter
            env = env_hex(env, (uint64_t*)&sysinfostruc.systables[systable_hpet_ptr], 1024*1024, 0);
        } else
        // manually override APIC address
        if(!kmemcmp(env, "apic=", 5)) {
            env += 5;
            // we only accept hex value for this parameter
            env = env_hex(env, (uint64_t*)&sysinfostruc.systables[systable_apic_ptr], 1024*1024, 0);
        } else
        // manually override IOAPIC address
        if(!kmemcmp(env, "ioapic=", 7)) {
            env += 7;
            // we only accept hex value for this parameter
            env = env_hex(env, (uint64_t*)&ioapic_addr, 1024*1024, 0);
        } else
        // disable networking
        if(!kmemcmp(env, "networking=", 11)) {
            env += 11;
            env = env_boolf(env, &networking);
        } else
        // disable sound
        if(!kmemcmp(env, "sound=", 6)) {
            env += 6;
            env = env_boolf(env, &sound);
        } else
        // rescue shell
        if(!kmemcmp(env, "rescueshell=", 12)) {
            env += 12;
            env = env_boolt(env, &sysinfostruc.rescueshell);
        } else
        // run first time turn on's ask for identity task
        if(!kmemcmp(env, "identity=", 9)) {
            env += 9;
            env = env_boolf(env, &identity);
        } else
        // maximum timeslice rate per second for a thread
        // to allocate CPU continously (1/quantum sec)
        if(!kmemcmp(env, "quantum=", 8)) {
            env += 8;
            env = env_dec(env, &sysinfostruc.quantum, 100, 10000);
        } else
        // maximum frame rate per second
        // suggested values 60-1000
        if(!kmemcmp(env, "fps=", 4)) {
            env += 4;
            env = env_dec(env, &fps, 10, 10000);
        } else
        // display layout
        if(!kmemcmp(env, "display=", 8)) {
            env += 8;
            env = env_display(env);
        } else
        // keyboard layout
        if(!kmemcmp(env, "keymap=", 7)) {
            env += 7;
            env = env_keymap(env);
        } else
#if DEBUG
        // output verbosity level
        if(!kmemcmp(env, "debug=", 6)) {
            env += 6;
            env = env_debug(env);
        } else
#endif
            env++;
    }
}
