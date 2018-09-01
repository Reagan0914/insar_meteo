
#include "array.hpp"
#include "utils.hpp"

pydoc(test, "test");

static py_ptr test(py_varargs)
{
    arrayd arr;
    np_ptr _arr = NULL;
    
    parse_varargs("O!", &PyArray_Type, &_arr);
    
    if(arr.import(_arr))
        return NULL;
    
    FOR(ii, 0, arr.rows()) {
        FOR(jj, 0, arr.cols())
            print("%lf ", arr(ii,jj));
        prints("\n");
    }
    
    Py_RETURN_NONE;
}

init_methods(inmet_aux,
             pymeth_varargs(test))
             
init_module(inmet_aux, "inmet_aux", 0.1)
