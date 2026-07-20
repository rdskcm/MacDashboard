// N7 research spike: enumerate Apple Silicon temperature sensors via the private
// IOHIDEventSystemClient API (the technique used by smctemp / Stats.app / TG Pro).
// These symbols are exported by IOKit.framework but not declared in public headers,
// so we declare them ourselves (extern) and link directly against the framework.
//
// Build:  clang -O2 -framework CoreFoundation -framework IOKit thermal_probe.c -o thermal_probe
// Run:    ./thermal_probe            (single enumeration + read, prints name<TAB>value)
//         ./thermal_probe -timing N  (repeat full enumeration+read N times, print elapsed ms per run)

#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timeStamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#define kHIDPageAppleVendor 0xff00
#define kHIDUsageAppleVendorTemperatureSensor 0x0005
#define kIOHIDEventTypeTemperature 15

static int32_t IOHIDEventFieldBase(int32_t type) { return type << 16; }

static double now_ms(void) {
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t t = mach_absolute_time();
    return (double)t * tb.numer / tb.denom / 1e6;
}

// Runs one full enumeration + read pass. If names/values are non-NULL, appends results
// (used for the single-shot "print everything" mode). Returns count of sensors found.
static int run_once(int print) {
    CFAllocatorRef allocator = kCFAllocatorDefault;
    IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(allocator);
    if (!system) {
        fprintf(stderr, "ERROR: IOHIDEventSystemClientCreate returned NULL\n");
        return -1;
    }

    int pageVal = kHIDPageAppleVendor;
    int usageVal = kHIDUsageAppleVendorTemperatureSensor;
    CFNumberRef page = CFNumberCreate(allocator, kCFNumberIntType, &pageVal);
    CFNumberRef usage = CFNumberCreate(allocator, kCFNumberIntType, &usageVal);
    CFStringRef keys[2] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    CFTypeRef values[2] = { page, usage };
    CFDictionaryRef match = CFDictionaryCreate(allocator, (const void **)keys, values, 2,
                                                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    IOHIDEventSystemClientSetMatching(system, match);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);

    int count = 0;
    if (services) {
        CFIndex n = CFArrayGetCount(services);
        for (CFIndex i = 0; i < n; i++) {
            IOHIDServiceClientRef sc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            CFStringRef name = (CFStringRef)IOHIDServiceClientCopyProperty(sc, CFSTR("Product"));
            char nameBuf[256] = {0};
            if (name) {
                CFStringGetCString(name, nameBuf, sizeof(nameBuf), kCFStringEncodingUTF8);
                CFRelease(name);
            } else {
                snprintf(nameBuf, sizeof(nameBuf), "<unnamed #%ld>", (long)i);
            }

            IOHIDEventRef event = IOHIDServiceClientCopyEvent(sc, kIOHIDEventTypeTemperature, 0, 0);
            double temp = NAN;
            if (event) {
                temp = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(kIOHIDEventTypeTemperature));
                CFRelease(event);
            }
            if (print) {
                printf("%s\t%.3f\n", nameBuf, temp);
            }
            count++;
        }
        CFRelease(services);
    } else {
        if (print) fprintf(stderr, "WARNING: IOHIDEventSystemClientCopyServices returned NULL\n");
    }

    CFRelease(match);
    CFRelease(page);
    CFRelease(usage);
    CFRelease(system);
    return count;
}

int main(int argc, char **argv) {
    if (argc >= 3 && strcmp(argv[1], "-timing") == 0) {
        int reps = atoi(argv[2]);
        if (reps < 1) reps = 1;
        double *durations = malloc(sizeof(double) * reps);
        for (int i = 0; i < reps; i++) {
            double t0 = now_ms();
            int c = run_once(0);
            double t1 = now_ms();
            durations[i] = t1 - t0;
            fprintf(stderr, "run %d: %.3f ms (sensors=%d)\n", i + 1, durations[i], c);
        }
        double sum = 0, mn = durations[0], mx = durations[0];
        for (int i = 0; i < reps; i++) {
            sum += durations[i];
            if (durations[i] < mn) mn = durations[i];
            if (durations[i] > mx) mx = durations[i];
        }
        printf("min=%.3f avg=%.3f max=%.3f (n=%d) ms\n", mn, sum / reps, mx, reps);
        free(durations);
        return 0;
    }

    int c = run_once(1);
    if (c < 0) return 1;
    fprintf(stderr, "Total sensors found: %d\n", c);
    return 0;
}
