import numpy as np
cimport cython
from fused_types cimport floating, number

cdef extern from "math.h":
    double sqrt(double x) nogil
    double floor (double x) nogil

@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline floating _apply_affine_3d_x0(number x0, number x1, number x2, 
                                         floating[:,:] affine) nogil:
    r'''
    Returns the first component of the product of affine by (x0, x1, x2)
    '''
    return affine[0,0]*x0 + affine[0,1]*x1 + affine[0,2]*x2 + affine[0,3]

@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline floating _apply_affine_3d_x1(number x0, number x1, number x2,
                                         floating[:,:] affine) nogil:
    r'''
    Returns the second component of the product of affine by (x0, x1, x2)
    '''
    return affine[1,0]*x0 + affine[1,1]*x1 + affine[1,2]*x2 + affine[1,3]

@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline floating _apply_affine_3d_x2(number x0, number x1, number x2,
                                         floating[:,:] affine) nogil:
    r'''
    Returns the third component of the product of affine by (x0, x1, x2)
    '''
    return affine[2,0]*x0 + affine[2,1]*x1 + affine[2,2]*x2 + affine[2,3]

@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline floating _apply_affine_2d_x0(number x0, number x1, 
                                         floating[:,:] affine) nogil:
    r'''
    Returns the first component of the product of affine by (x0, x1)
    '''
    return affine[0,0]*x0 + affine[0,1]*x1 + affine[0,2]

@cython.boundscheck(False)
@cython.wraparound(False)
cdef inline floating _apply_affine_2d_x1(number x0, number x1,
                                         floating[:,:] affine) nogil:
    r'''
    Returns the second component of the product of affine by (x0, x1)
    '''
    return affine[1,0]*x0 + affine[1,1]*x1 + affine[1,2]

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void _compose_vector_fields(floating[:,:,:] d1, floating[:,:,:] d2, 
                                 floating[:,:,:] comp, floating[:] stats):
    r'''
    Computes the composition of the two 2-D displacemements d1 and d2 defined by
    comp[r, c] = d2(d1[r, c]) for each (r,c) in the domain of d1. The evaluation
    of d2 at non-lattice points is computed using trilinear interpolation. The 
    result is stored in comp.

    Parameters
    ----------
    d1 : array, shape (R, C, 2)
        first 2-D displacement field to be applied. R, C are the number of rows
        and columns of the displacement field d1, respectively.
    d2 : array, shape (R', C', 2)
        second displacement field to be applied. R', C' are the number of rows
        and columns of the displacement field d2, respectively.
    comp : array, shape (R, C, 2), same dimension as d1
        on output, this array will contain the composition of the two fields
    stats : array, shape (3,)
        on output, this array will contain three statistics of the vector norms
        of the composition (maximum, mean, standard_deviation)

    Notes
    -----
    If d1[r,c] lies outside the domain of d2, then comp[r,c] will contain a zero
    vector.
    '''
    cdef:
        int nr1=d1.shape[0]
        int nc1=d1.shape[1]
        int nr2=d2.shape[0]
        int nc2=d2.shape[1]
        int cnt=0
        floating maxNorm=0
        floating meanNorm=0
        floating stdNorm=0
        floating nn
        int i,j,ii,jj
        floating dii, djj, alpha, beta, calpha, cbeta
    comp[...]=0
    for i in range(nr1):
        for j in range(nc1):
            dii=i+d1[i,j,0]
            djj=j+d1[i,j,1]
            if((dii < 0) or (nr2-1 < dii) or (djj < 0) or (nc2-1 < djj)):
                continue
            ii=ifloor(dii)
            jj=ifloor(djj)
            if((ii < 0) or (nr2 <= ii) or (jj < 0) or (nc2 <= jj) ):
                continue
            calpha=dii-ii
            cbeta=djj-jj
            alpha=1-calpha
            beta=1-cbeta
            comp[i,j,0]=d1[i,j,0]
            comp[i,j,1]=d1[i,j,1]
            #top-left
            comp[i,j,0]+=alpha*beta*d2[ii,jj,0]
            comp[i,j,1]+=alpha*beta*d2[ii,jj,1]
            #top-right
            jj+=1
            if(jj < nc2):
                comp[i,j,0]+=alpha*cbeta*d2[ii,jj,0]
                comp[i,j,1]+=alpha*cbeta*d2[ii,jj,1]
            #bottom-right
            ii+=1
            if((ii >= 0) and (jj >= 0) and (ii < nr2)and (jj < nc2)):
                comp[i,j,0]+=calpha*cbeta*d2[ii,jj,0]
                comp[i,j,1]+=calpha*cbeta*d2[ii,jj,1]
            #bottom-left
            jj-=1
            if((ii >= 0) and (jj >= 0) and (ii < nr2) and (jj < nc2)):
                comp[i,j,0]+=calpha*beta*d2[ii,jj,0]
                comp[i,j,1]+=calpha*beta*d2[ii,jj,1]
            #consider only displacements that land inside the image
            if((0 <= dii <= nr2-1) and (0 <= djj <= nc2-1)):
                nn=comp[i,j,0]**2+comp[i,j,1]**2
                if(maxNorm < nn):
                    maxNorm=nn
                meanNorm+=nn
                stdNorm+=nn*nn
                cnt+=1
    meanNorm/=cnt
    stats[0]=sqrt(maxNorm)
    stats[1]=sqrt(meanNorm)
    stats[2]=sqrt(stdNorm/cnt - meanNorm*meanNorm)

def compose_vector_fields(floating[:,:,:] d1, floating[:,:,:] d2):
    r'''
    Computes the composition of the two 2-D displacemements d1 and d2 defined by
    comp[r, c] = d2(d1[r, c]) for each (r,c) in the domain of d1. The evaluation
    of d2 at non-lattice points is computed using trilinear interpolation.

    Parameters
    ----------
    d1 : array, shape (R, C, 2)
        first displacement field to be applied. R, C are the number of rows
        and columns of the displacement field, respectively.
    d2 : array, shape (R', C', 2)
        second displacement field to be applied. R', C' are the number of rows
        and columns of the displacement field, respectively.

    Returns
    -------
    comp : array, shape (R, C, 2), same dimension as d1
        on output, this array will contain the composition of the two fields
    stats : array, shape (3,)
        on output, this array will contain three statistics of the vector norms
        of the composition (maximum, mean, standard_deviation) 
    '''
    cdef:
        floating[:,:,:] comp=np.zeros_like(d1)
        floating[:] stats=np.zeros(shape=(3,), dtype=cython.typeof(d1[0,0,0]))
    _compose_vector_fields(d1, d2, comp, stats)
    return comp, stats

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void _compose_vector_fields_3d(floating[:,:,:,:] d1, floating[:,:,:,:] d2, 
                                    floating[:,:,:,:] comp, floating[:] stats):
    r'''
    Computes the composition of the two 3-D displacemements d1 and d2 defined by
    comp[s, r, c] = d2(d1[s, r, c]) for each (s,r,c) in the domain of d1. 
    The evaluation of d2 at non-lattice points is computed using trilinear
    interpolation. The result is stored in comp.

    Parameters
    ----------
    d1 : array, shape (S, R, C, 3)
        first 3-D displacement field to be applied. S, R, C are the number of
        slices, rows and columns of the displacement field d1, respectively.
    d2 : array, shape (S', R', C', 3)
        second displacement field to be applied. S', R', C' are the number of
        slices, rows and columns of the displacement field d2, respectively.
    comp : array, shape (S, R, C, 3), same dimension as d1
        on output, this array will contain the composition of the two fields
    stats : array, shape (3,)
        on output, this array will contain three statistics of the vector norms
        of the composition (maximum, mean, standard_deviation)

    Notes
    -----
    If d1[s,r,c] lies outside the domain of d2, then comp[s,r,c] will contain a
    zero vector.
    '''
    cdef:
        int ns1=d1.shape[0]
        int nr1=d1.shape[1]
        int nc1=d1.shape[2]
        int ns2=d2.shape[0]
        int nr2=d2.shape[1]
        int nc2=d2.shape[2]
        int cnt=0
        int k,i,j, kk, ii, jj
        floating maxNorm=0
        floating meanNorm=0
        floating stdNorm=0
        floating dkk, dii, djj
        floating alpha, beta, gamma, calpha, cbeta, cgamma, nn
    comp[...]=0
    for k in range(ns1):
        for i in range(nr1):
            for j in range(nc1):
                dkk=k+d1[k,i,j,0]
                dii=i+d1[k,i,j,1]
                djj=j+d1[k,i,j,2]
                if((dii<0) or (djj<0) or (dkk<0) or 
                    (dii>nr2-1) or (djj>nc2-1) or (dkk>ns2-1)):
                    continue
                #---top-left
                kk=ifloor(dkk)
                ii=ifloor(dii)
                jj=ifloor(djj)
                if((ii<0) or (jj<0) or (kk<0) or 
                    (ii>=nr2) or (jj>=nc2) or (kk>=ns2)):
                    continue
                cgamma=dkk-kk
                calpha=dii-ii#by definition these factors are nonnegative
                cbeta=djj-jj
                alpha=1-calpha
                beta=1-cbeta
                gamma=1-cgamma
                comp[k,i,j,0]=d1[k,i,j,0]
                comp[k,i,j,1]=d1[k,i,j,1]
                comp[k,i,j,2]=d1[k,i,j,2]
                comp[k,i,j,0]+=alpha*beta*gamma*d2[kk,ii,jj,0]
                comp[k,i,j,1]+=alpha*beta*gamma*d2[kk,ii,jj,1]
                comp[k,i,j,2]+=alpha*beta*gamma*d2[kk,ii,jj,2]
                #---top-right
                jj+=1
                if(jj<nc2):
                    comp[k,i,j,0]+=alpha*cbeta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=alpha*cbeta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=alpha*cbeta*gamma*d2[kk,ii,jj,2]
                #---bottom-right
                ii+=1
                if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                    comp[k,i,j,0]+=calpha*cbeta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=calpha*cbeta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=calpha*cbeta*gamma*d2[kk,ii,jj,2]
                #---bottom-left
                jj-=1
                if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                    comp[k,i,j,0]+=calpha*beta*gamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=calpha*beta*gamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=calpha*beta*gamma*d2[kk,ii,jj,2]
                kk+=1
                if(kk<ns2):
                    ii-=1
                    comp[k,i,j,0]+=alpha*beta*cgamma*d2[kk,ii,jj,0]
                    comp[k,i,j,1]+=alpha*beta*cgamma*d2[kk,ii,jj,1]
                    comp[k,i,j,2]+=alpha*beta*cgamma*d2[kk,ii,jj,2]
                    jj+=1
                    if(jj<nc2):
                        comp[k,i,j,0]+=alpha*cbeta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=alpha*cbeta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=alpha*cbeta*cgamma*d2[kk,ii,jj,2]
                    #---bottom-right
                    ii+=1
                    if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                        comp[k,i,j,0]+=calpha*cbeta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=calpha*cbeta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=calpha*cbeta*cgamma*d2[kk,ii,jj,2]
                    #---bottom-left
                    jj-=1
                    if((ii>=0) and (jj>=0) and (ii<nr2) and (jj<nc2)):
                        comp[k,i,j,0]+=calpha*beta*cgamma*d2[kk,ii,jj,0]
                        comp[k,i,j,1]+=calpha*beta*cgamma*d2[kk,ii,jj,1]
                        comp[k,i,j,2]+=calpha*beta*cgamma*d2[kk,ii,jj,2]
                if((0<= dkk<= ns2-1) and (0<= dii<=nr2-1) and (0<= djj<= nc2-1)):
                    nn=comp[k,i,j,0]**2+comp[k,i,j,1]**2+comp[k,i,j,2]**2
                    if(maxNorm<nn):
                        maxNorm=nn
                    meanNorm+=nn
                    stdNorm+=nn*nn
                    cnt+=1
    meanNorm/=cnt
    stats[0]=sqrt(maxNorm)
    stats[1]=sqrt(meanNorm)
    stats[2]=sqrt(stdNorm/cnt - meanNorm*meanNorm)

def compose_vector_fields_3d(floating[:,:,:,:] d1, floating[:,:,:,:] d2):
    r'''
    Computes the composition of the two 3-D displacemements d1 and d2 defined by
    comp[s, r, c] = d2(d1[s, r, c]) for each (s,r,c) in the domain of d1. The
    evaluation of d2 at non-lattice points is computed using trilinear 
    interpolation.

    Parameters
    ----------
    d1 : array, shape (S, R, C, 3)
        first 3-D displacement field to be applied. S, R, C are the number of
        slices, rows and columns of the displacement field, respectively.
    d2 : array, shape (S', R', C', 3)
        second displacement field to be applied. S', R', C' are the number of
        slices, rows and columns of the displacement field, respectively.

    Returns
    -------
    comp : array, shape (S, R, C, 3), same dimension as d1
        on output, this array will contain the composition of the two fields
    stats : array, shape (3,)
        on output, this array will contain three statistics of the vector norms
        of the composition (maximum, mean, standard_deviation) 
    '''
    cdef:
        floating[:,:,:,:] comp=np.zeros_like(d1)
        floating[:] stats=np.zeros(shape=(3,), dtype=cython.typeof(d1[0,0,0,0]))
    _compose_vector_fields_3d(d1, d2, comp, stats)
    return comp, stats

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def invert_vector_field_fixed_point(floating[:,:,:] d, integral[:] inv_shape, 
                                    int max_iter, floating tolerance,
                                    floating[:,:,:] start=None):
    r'''
    Computes the inverse of the given 2-D displacement field d using the 
    fixed-point algorithm.

    Parameters
    ----------
    d : array, shape (R, C, 2)
        the 2-D displacement field to be inverted
    inv_shape : array, shape (2,)
        the expected shape of the inverse displacement field.  
    max_iter : int
        maximum number of iterations to be performed
    tolerance : float
        maximum tolerated inversion error
    start : array, shape (R', C')
        an aproximation to the inverse displacemnet field (if no aproximation
        is available, None can be provided and the start displacement fieldwill 
        be zero)
    Notes
    -----
    The 'inversion error' at iteration t is defined as the mean norm of the
    displacement vectors of the input displacement field composed with the
    inverse at iteration t. If inv_shape is None, the shape of the resulting
    inverse will be the same as the input displacement field.
    '''
    cdef:
        int nr1=d.shape[0]
        int nc1=d.shape[1]
        int nr2, nc2, iter_count, current
        floating difmag, mag
        floating epsilon=0.25
        floating error = 1 + tolerance
    if inv_shape != None:
        nr2, nc2 = inv_shape[0], inv_shape[1]
    else:
        nr2, nc2 = nr1, nc1
    cdef:
        floating[:] stats=np.zeros(shape=(2,), dtype=cython.typeof(d[0,0,0]))
        floating[:] substats = np.empty(shape = (3,), dtype=cython.typeof(d[0,0,0]))
        floating[:,:,:] p=np.zeros(shape=(nr2,nc2,2), dtype=cython.typeof(d[0,0,0]))
        floating[:,:,:] q=np.zeros(shape=(nr2,nc2,2), dtype=cython.typeof(d[0,0,0]))
    if start!=None:
        p[...]=start
    iter_count = 0
    while (iter_count < max_iter) and (tolerance < error):
        p, q = q, p
        _compose_vector_fields(q, d, p, substats)
        difmag=0
        error=0
        for i in range(nr2):
            for j in range(nc2):
                mag=sqrt(p[i,j,0]**2 + p[i,j,1]**2)
                p[i,j,0] = q[i,j,0] - epsilon * p[i,j,0]
                p[i,j,1] = q[i,j,1] - epsilon * p[i,j,1]
                error+=mag
                if(difmag<mag):
                    difmag=mag
        error/=(nr2*nc2)
        iter_count+=1
    stats[0]=substats[1]
    stats[1]=iter_count
    return p

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
def invert_vector_field_fixed_point_3d(floating[:,:,:,:] d, int[:] inverse_shape, 
                                       int max_iter, floating tolerance, 
                                       floating[:,:,:,:] start=None):
    r'''
    Computes the inverse of the given 3-D displacement field d using the 
    fixed-point algorithm.

    Parameters
    ----------
    d : array, shape (S, R, C, 3)
        the 3-D displacement field to be inverted
    inv_shape : array, shape (3,)
        the expected shape of the inverse displacement field.
    max_iter : int
        maximum number of iterations to be performed
    tolerance : float
        maximum tolerated inversion error
    start : array, shape (R', C')
        an aproximation to the inverse displacemnet field (if no aproximation
        is available, None can be provided and the start displacement fieldwill 
        be zero)

    Notes
    -----
    The 'inversion error' at iteration t is defined as the mean norm of the
    displacement vectors of the input displacement field composed with the
    inverse at iteration t. If inv_shape is None, the shape of the resulting
    inverse will be the same as the input displacement field.
    '''
    cdef:
        int ns1=d.shape[0]
        int nr1=d.shape[1]
        int nc1=d.shape[2]
        int ns2, nr2, nc2
        int k, i, j, iter_count
    if inverseShape!=None:
        ns2, nr2, nc2 = inverseShape[0], inverseShape[1], inverseShape[2]
    else:
        ns2, nr2, nc2 = ns1, nr1, nc1
    cdef:
        floating[:] stats=np.empty(shape=(2,), dtype=cython.typeof(d[0,0,0,0]))
        floating[:] substats=np.empty(shape=(3,), dtype=cython.typeof(d[0,0,0,0]))
        floating[:,:,:,:] p=np.zeros((ns2, nr2, nc2, 3), dtype=cython.typeof(d[0,0,0,0]))
        floating[:,:,:,:] q=np.zeros((ns2, nr2, nc2, 3), dtype=cython.typeof(d[0,0,0,0]))
        floating error=1+tolerance
        floating epsilon = 0.5
        floating mag, difmag
    if start!=None:
        p[...] = start
    iter_count = 0
    while (iter_count < max_iter) and (tolerance < error):
        p, q = q, p
        _compose_vector_fields_3d(q, d, p, substats)
        difmag=0
        error=0
        for k in range(ns2):
            for i in range(nr2):
                for j in range(nc2):
                    mag=sqrt(p[k,i,j,0]**2 + p[k,i,j,1]**2 + p[k,i,j,2]**2)
                    p[k,i,j,0] = q[k,i,j,0] - epsilon * p[k,i,j,0]
                    p[k,i,j,1] = q[k,i,j,1] - epsilon * p[k,i,j,1]
                    p[k,i,j,2] = q[k,i,j,2] - epsilon * p[k,i,j,2]
                    error+=mag
                    if(difmag<mag):
                        difmag=mag
        error/=(ns2*nr2*nc2)
        iter_count+=1
    stats[0]=error
    stats[1]=iter_count
    return p
