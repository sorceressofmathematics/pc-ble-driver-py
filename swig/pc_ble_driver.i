/* Copyright (c) 2014 Nordic Semiconductor. All Rights Reserved.
 *
 * The information contained herein is property of Nordic Semiconductor ASA.
 * Terms and conditions of usage are described in detail in NORDIC
 * SEMICONDUCTOR STANDARD SOFTWARE LICENSE AGREEMENT.
 *
 * Licensees are granted free, non-transferable use of the information. NO
 * WARRANTY of ANY KIND is provided. This heading must NOT be removed from
 * the file.
 *
 */

%module pc_ble_driver

%include "stdint.i"
%include "carrays.i"
%include "cpointer.i"

// Includes used in this transformation
%{
#include "sd_rpc.h"
#include "stdio.h"

#ifdef DEBUG
#include <pthread.h>
#endif // DEBUG

%}

// Requires special handling
%ignore sd_rpc_open;

// Ignore L2CAP APIs that will be replaced by L2CAP CoCs
%ignore sd_ble_l2cap_cid_register;
%ignore sd_ble_l2cap_cid_unregister;
%ignore sd_ble_l2cap_tx;
// Ignore event getter, handled by the connectivity device
%ignore sd_ble_evt_get;

// Grab the definitions
%include "config/platform.h"
%include "adapter.h"
%include "ble.h"
%include "ble_err.h"
%include "ble_gap.h"
%include "ble_gatt.h"
%include "ble_gatts.h"
%include "ble_gattc.h"
%include "ble_hci.h"
%include "ble_l2cap.h"
%include "ble_ranges.h"
%include "ble_types.h"
%include "nrf_error.h"
%include "sd_rpc.h"
%include "sd_rpc_types.h"

%pointer_functions(uint8_t, uint8)
%pointer_functions(uint16_t, uint16)

%array_class(uint8_t, uint8_array);
%array_class(uint16_t, uint16_array);
%array_class(ble_gattc_service_t, ble_gattc_service_array);
%array_class(ble_gattc_include_t, ble_gattc_include_array);
%array_class(ble_gattc_char_t, ble_gattc_char_array);
%array_class(ble_gattc_desc_t, ble_gattc_desc_array);
%array_class(ble_gattc_attr_info_t, ble_gattc_attr_info_array);
%array_class(ble_gattc_handle_value_t, ble_gattc_handle_value_array);

// Grab a Python function object as a Python object.
%typemap(in) PyObject *pyfunc {
    if (!PyCallable_Check($input)) {
        PyErr_SetString(PyExc_TypeError, "Need a callable object!");
        return NULL;
    }
    $1 = $input;
}
%rename(sd_rpc_open) sd_rpc_open_py;
extern PyObject* sd_rpc_open_py(PyObject *adapter, PyObject *py_status_handler, PyObject *py_evt_handler, PyObject *py_log_handler);

/* Event callback handling */
%{
static PyObject *my_pyevtcallback = NULL;

static void PythonEvtCallBack(adapter_t *adapter, ble_evt_t *ble_event)
{
    PyObject *func;
    PyObject *arglist;
    PyObject *adapter_obj;
    PyObject *ble_evt_obj;
    PyGILState_STATE gstate;
    ble_evt_t* copied_ble_event;

#if DEBUG
    unsigned long int tr;
    tr = (unsigned long int)pthread_self();
    printf("XXXX-XX-XX XX:XX:XX,XXX BIND tid:0x%lX\n", tr);
#endif // DEBUG

    if(my_pyevtcallback == NULL) {
        printf("Callback not set, returning\n");
        return;
    }

    func = my_pyevtcallback;

#if DEBUG
    printf("sizeof(ble_evt_t): %ld\n", sizeof(ble_evt_t));
    printf("ble_event->header.evt_len: %d\n", ble_event->header.evt_len);
    printf("ble_event->header.evt_id: %X\n", ble_event->header.evt_id);
    printf("sizeof(ble_evt_hdr_t): %ld\n", sizeof(ble_evt_hdr_t));
#endif // DEBUG

    // Do a copy of the event so that the Python developer is able to access the event after
    // this callback is complete. The event that is received in this function is allocated
    // on the stack of the function calling this function.
    copied_ble_event = (ble_evt_t*)malloc(sizeof(ble_evt_t));
    memcpy(copied_ble_event, ble_event, sizeof(ble_evt_t));

    // Handling of Python Global Interpretor Lock (GIL)
    gstate = PyGILState_Ensure();

    adapter_obj = SWIG_NewPointerObj(SWIG_as_voidptr(adapter), SWIGTYPE_p_adapter_t, 0 |  0 );
    // Create a Python object that points to the copied event, let the interpreter take care of
    // memory management of the copied event by setting the SWIG_POINTER_OWN flag.
    ble_evt_obj = SWIG_NewPointerObj(SWIG_as_voidptr(copied_ble_event), SWIGTYPE_p_ble_evt_t, SWIG_POINTER_OWN);
    arglist = Py_BuildValue("(OO)", adapter_obj, ble_evt_obj);

    PyEval_CallObject(func, arglist);

    Py_XDECREF(adapter_obj);
    Py_XDECREF(ble_evt_obj);
    Py_DECREF(arglist);

    PyGILState_Release(gstate);
}
%}

/* Status callback handling */
%{
static PyObject *my_pystatuscallback = NULL;

static void PythonStatusCallBack(adapter_t *adapter, sd_rpc_app_status_t status_code, const char * status_message)
{
    PyObject *func;
    PyObject *arglist;
    PyObject *result;
    PyObject *adapter_obj;
    PyObject *status_code_obj;
    PyObject *status_message_obj;
    PyGILState_STATE gstate;

    func = my_pystatuscallback;

    if(my_pystatuscallback == NULL) {
        printf("Callback not set, returning\n");
        return;
    }

    // For information regarding GIL and copying of data, please look at
    // function PythonEvtCallBack.

#if DEBUG
    unsigned long int tr;
    tr = (unsigned long int)pthread_self();
    printf("XXXX-XX-XX XX:XX:XX,XXX BIND tid:0x%lX\n", tr);
#endif // DEBUG

    gstate = PyGILState_Ensure();

    adapter_obj = SWIG_NewPointerObj(SWIG_as_voidptr(adapter), SWIGTYPE_p_adapter_t, 0 |  0 );
    status_code_obj = SWIG_From_int((int)(status_code));

    // SWIG_Python_str_FromChar boils down to PyString_FromString which does a copy of log_message string
    status_message_obj = SWIG_Python_str_FromChar((const char *)status_message);
    arglist = Py_BuildValue("(OOO)", adapter_obj, status_code_obj, status_message_obj);

    result = PyEval_CallObject(func, arglist);

    Py_XDECREF(adapter_obj);
    Py_XDECREF(status_code_obj);
    Py_XDECREF(status_message_obj);
    Py_DECREF(arglist);
    Py_XDECREF(result);

    PyGILState_Release(gstate);
}
%}

/* Log callback handling */
%{
static PyObject *my_pylogcallback = NULL;

static void PythonLogCallBack(adapter_t *adapter, sd_rpc_log_severity_t severity, const char * log_message)
{
    PyObject *func;
    PyObject *arglist;
    PyObject *result;
    PyObject *adapter_obj;
    PyObject *severity_obj;
    PyObject *message_obj;
    PyGILState_STATE gstate;

    func = my_pylogcallback;

    if(my_pylogcallback == NULL) {
        printf("Callback not set, returning\n");
        return;
    }

    // For information regarding GIL and copying of data, please look at
    // function PythonEvtCallBack.

#if DEBUG
    unsigned long int tr;
    tr = (unsigned long int)pthread_self();
    printf("XXXX-XX-XX XX:XX:XX,XXX BIND tid:0x%lX\n", tr);
#endif // DEBUG

    gstate = PyGILState_Ensure();

    adapter_obj = SWIG_NewPointerObj(SWIG_as_voidptr(adapter), SWIGTYPE_p_adapter_t, 0 |  0 );
    severity_obj = SWIG_From_int((int)(severity));

    // SWIG_Python_str_FromChar boils down to PyString_FromString which does a copy of log_message string
    message_obj = SWIG_Python_str_FromChar((const char *)log_message);
    arglist = Py_BuildValue("(OOO)", adapter_obj, severity_obj, message_obj);

    result = PyEval_CallObject(func, arglist);

    Py_XDECREF(adapter_obj);
    Py_XDECREF(message_obj);
    Py_XDECREF(severity_obj);
    Py_DECREF(arglist);
    Py_XDECREF(result);

    PyGILState_Release(gstate);
}
%}

%{
// Open the RPC and set Python function objects as a callback functions
PyObject* sd_rpc_open_py(PyObject *adapter, PyObject *py_status_handler, PyObject *py_evt_handler, PyObject *py_log_handler)
{

    PyObject *resultobj = 0;
    adapter_t *arg1 = (adapter_t *) 0;
    void *argp1 = 0 ;
    int res1 = 0 ;
    uint32_t result;
 
    res1 = SWIG_ConvertPtr(adapter, &argp1,SWIGTYPE_p_adapter_t, 0 |  0 );
    if (!SWIG_IsOK(res1)) {
      SWIG_exception_fail(SWIG_ArgError(res1), "in method '" "sd_rpc_open" "', argument " "1"" of type '" "adapter_t *""'"); 
    }

    arg1 = (adapter_t * ) (argp1);

    Py_XDECREF(my_pystatuscallback);  /* Remove any existing callback object */
    Py_XDECREF(my_pyevtcallback);  /* Remove any existing callback object */
    Py_XDECREF(my_pylogcallback); /* Remove any existing callback object */
    Py_XINCREF(py_status_handler);
    Py_XINCREF(py_evt_handler);
    Py_XINCREF(py_log_handler);
    my_pystatuscallback = py_status_handler;
    my_pyevtcallback = py_evt_handler;
    my_pylogcallback = py_log_handler;
    
    result = sd_rpc_open(arg1, PythonStatusCallBack, PythonEvtCallBack, PythonLogCallBack);
    resultobj = SWIG_From_unsigned_SS_int((unsigned int) (result));
    return resultobj;

fail:
    return NULL;
}
%}

