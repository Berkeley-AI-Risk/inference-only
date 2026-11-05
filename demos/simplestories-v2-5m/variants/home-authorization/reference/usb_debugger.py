"""USB-only reset of the fixed test-board debugger.

Caller must hold the board lock and close all serial/programmer handles.
No FPGA configuration or flash command is sent.
"""
import ctypes as c,subprocess

def reset_known_debugger(perform_reset=True):
    if subprocess.run(['/usr/sbin/lsof','/dev/cu.usbserial-20250303170','/dev/cu.usbserial-20250303171'],capture_output=True,text=True).stdout.strip():
        raise RuntimeError('Tang serial port owned; no reset attempted')
    class Descriptor(c.Structure):
        _fields_=[('length',c.c_uint8),('type',c.c_uint8),('usb',c.c_uint16),
                  ('device_class',c.c_uint8),('subclass',c.c_uint8),('protocol',c.c_uint8),('packet_size',c.c_uint8),
                  ('vid',c.c_uint16),('pid',c.c_uint16),('version',c.c_uint16),
                  ('manufacturer',c.c_uint8),('product',c.c_uint8),('serial',c.c_uint8),('configurations',c.c_uint8)]
    u=c.CDLL('/opt/homebrew/lib/libusb-1.0.dylib')
    def decl(name,args,ret):
        f=getattr(u,name);f.argtypes=args;f.restype=ret;return f
    init=decl('libusb_init',[c.POINTER(c.c_void_p)],c.c_int)
    get_list=decl('libusb_get_device_list',[c.c_void_p,c.POINTER(c.POINTER(c.c_void_p))],c.c_ssize_t)
    get_desc=decl('libusb_get_device_descriptor',[c.c_void_p,c.POINTER(Descriptor)],c.c_int)
    open_device=decl('libusb_open',[c.c_void_p,c.POINTER(c.c_void_p)],c.c_int)
    get_string=decl('libusb_get_string_descriptor_ascii',[c.c_void_p,c.c_uint8,c.c_void_p,c.c_int],c.c_int)
    reset=decl('libusb_reset_device',[c.c_void_p],c.c_int)
    close=decl('libusb_close',[c.c_void_p],None)
    free_list=decl('libusb_free_device_list',[c.POINTER(c.c_void_p),c.c_int],None)
    exit_usb=decl('libusb_exit',[c.c_void_p],None)
    error_name=decl('libusb_error_name',[c.c_int],c.c_char_p)
    ctx=c.c_void_p();assert init(c.byref(ctx))==0
    devices=c.POINTER(c.c_void_p)();handles=[];record={'reset_requested':perform_reset,'matches':[]}
    try:
        count=get_list(ctx,c.byref(devices));assert count>=0
        for i in range(count):
            d=Descriptor();assert get_desc(devices[i],c.byref(d))==0
            if (d.vid,d.pid)!=(0x0403,0x6010):continue
            h=c.c_void_p();code=open_device(devices[i],c.byref(h))
            if code:raise RuntimeError('Cannot open FTDI debugger: '+error_name(code).decode())
            buf=c.create_string_buffer(256);size=get_string(h,d.serial,buf,len(buf))
            serial=buf.raw[:size].decode()if size>=0 else''
            if serial=='2025030317':
                handles.append(h);record['matches'].append({'vid':d.vid,'pid':d.pid,'serial':serial})
            else:close(h)
        assert len(handles)==1,'Expected exactly one matching Tang debugger'
        if perform_reset:
            code=reset(handles[0]);record['reset_code']=code;record['reset_name']=error_name(code).decode()
    finally:
        for h in handles:close(h)
        if devices:free_list(devices,1)
        exit_usb(ctx)
    if perform_reset and record['reset_code'] not in (0,-5):
        raise RuntimeError('USB debugger reset failed: '+record['reset_name'])
    return record
