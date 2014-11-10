/*
 * simple_vector.c --
 *
 * Simple vector space implementation for OptimPack library.
 *
 *-----------------------------------------------------------------------------
 *
 * Copyright (c) 2014 Éric Thiébaut
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 *-----------------------------------------------------------------------------
 */

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>
#include <assert.h>

#include "optimpack-private.h"

#ifndef SINGLE_PRECISION
#  error expecting macro SINGLE_PRECISION to be defined
#endif

#if SINGLE_PRECISION
#  define REAL     float
#  define ABS(x)   fabsf(x)
#  define SQRT(x)  sqrtf(x)
#  define ALPHA    _alpha
#  define BETA     _beta
#  define GAMMA    _gamma
#  define ZERO     0.0f
#  define ONE      1.0f
#else
#  define REAL     double
#  define ABS(x)   fabs(x)
#  define SQRT(x)  sqrt(x)
#  define ALPHA    alpha
#  define BETA	   beta
#  define GAMMA	   gamma
#  define ZERO     0.0
#  define ONE      1.0
#endif

typedef struct _simple_vector simple_vector_t;
struct _simple_vector {
  opk_vector_t base;
  REAL* data;
};

#define DATA(v) ((simple_vector_t*)(v))->data

static void
finalize(opk_vspace_t* vspace)
{
  if (vspace != NULL) {
    free((void*)vspace);
  }
}

static opk_vector_t*
create(opk_vspace_t* vspace)
{
  const size_t offset = ROUND_UP(sizeof(simple_vector_t), sizeof(REAL));
  size_t size = offset + vspace->size*sizeof(REAL);
  opk_vector_t* v = opk_valloc(vspace, size);
  if (v != NULL) {
    ((simple_vector_t*)v)->data = (REAL*)(((char*)v) + offset);
  }
  return v;
}

static void
delete(opk_vspace_t* vspace,
       opk_vector_t* v)
{
  opk_vfree(v);
}

static void
fill(opk_vspace_t* vspace, opk_vector_t* vect, double alpha)
{
  REAL* x = DATA(vect);
  opk_index_t j, n = vspace->size;
  if (alpha == 0.0) {
    memset(x, 0, n*sizeof(REAL));
  } else {
#if SINGLE_PRECISION
    REAL ALPHA = (REAL)alpha;
#endif
    for (j = 0; j < n; ++j) {
      x[j] = ALPHA;
    }
  }
}

static double
norm1(opk_vspace_t* vspace,
      const opk_vector_t* vx)
{
  REAL result = ZERO;
  const REAL* x = DATA(vx);
  opk_index_t j, n = vspace->size;
  for (j = 0; j < n; ++j) {
    result += ABS(x[j]);
  }
  return (double)result;
}

static double
norm2(opk_vspace_t* vspace,
      const opk_vector_t* vx)
{
  REAL result = ZERO;
  const REAL* x = DATA(vx);
  opk_index_t j, n = vspace->size;
  for (j = 0; j < n; ++j) {
    REAL xj = x[j];
    result += xj*xj;
  }
  return (double)SQRT(result);
}

static double
norminf(opk_vspace_t* vspace,
        const opk_vector_t* vx)
{
  REAL result = ZERO;
  const REAL* x = DATA(vx);
  opk_index_t j, n = vspace->size;
  for (j = 0; j < n; ++j) {
    REAL axj = ABS(x[j]);
    if (axj > result) {
      result = axj;
    }
  }
  return (double)result;
}

static double
dot(opk_vspace_t* vspace,
    const opk_vector_t* vx,
    const opk_vector_t* vy)
{
  REAL result = ZERO;
  const REAL* x = DATA(vx);
  const REAL* y = DATA(vy);
  opk_index_t j, n = vspace->size;
  for (j = 0; j < n; ++j) {
    result += x[j]*y[j];
  }
  return (double)result;
}

static void
copy(opk_vspace_t* vspace,
     opk_vector_t* vdst, const opk_vector_t* vsrc)
{
  REAL* dst = DATA(vdst);
  const REAL* src = DATA(vsrc);
  if (dst != src) {
    memcpy(dst, src, vspace->size*sizeof(REAL));
  }
}

static void
swap(opk_vspace_t* vspace,
     opk_vector_t* vx, opk_vector_t* vy)
{
  REAL* x = DATA(vx);
  REAL* y = DATA(vy);
  if (x != y) {
    opk_index_t j, n = vspace->size;
    for (j = 0; j < n; ++j) {
      REAL t = x[j];
      x[j] = y[j];
      y[j] = t;
    }
  }
}

static void
scale(opk_vspace_t* vspace, opk_vector_t* vdst,
      double alpha, const opk_vector_t* vsrc)
{
  /* Note: we already know that ALPHA is neither 0 nor 1. */
  REAL* dst = DATA(vdst);
  const REAL* src = DATA(vsrc);
  opk_index_t j, n = vspace->size;
#if SINGLE_PRECISION
  REAL ALPHA = (REAL)alpha;
#endif
  for (j = 0; j < n; ++j) {
    dst[j] = ALPHA*src[j];
  }
}

static void
axpby(opk_vspace_t* vspace, opk_vector_t* vdst,
      double alpha, const opk_vector_t* vx,
      double beta,  const opk_vector_t* vy)
{
  /* Note: we already know that neither ALPHA nor BETA is 0. */
  const REAL* x = DATA(vx);
  const REAL* y = DATA(vy);
  REAL* dst = DATA(vdst);
  opk_index_t j, n = vspace->size;
  if (alpha == 1.0) {
    if (beta == 1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = x[j] + y[j];
      }
    } else if (beta == -1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = x[j] - y[j];
      }
    } else {
#if SINGLE_PRECISION
      REAL BETA = (REAL)beta;
#endif
      for (j = 0; j < n; ++j) {
        dst[j] = x[j] + BETA*y[j];
      }
    }
  } else if (alpha == -1.0) {
    if (beta == 1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = y[j] - x[j];
      }
    } else if (beta == -1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = -y[j] - x[j];
      }
    } else {
#if SINGLE_PRECISION
      REAL BETA = (REAL)beta;
#endif
      for (j = 0; j < n; ++j) {
        dst[j] = BETA*y[j] - x[j];
      }
    }
  } else {
#if SINGLE_PRECISION
    REAL ALPHA = (REAL)alpha;
#endif
    if (beta == 1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = ALPHA*x[j] + y[j];
      }
    } else if (beta == -1.0) {
      for (j = 0; j < n; ++j) {
        dst[j] = ALPHA*x[j] - y[j];
      }
    } else {
#if SINGLE_PRECISION
      REAL BETA = (REAL)beta;
#endif
      for (j = 0; j < n; ++j) {
        dst[j] = ALPHA*x[j] + BETA*y[j];
      }
    }
  }
}

static void
axpbypcz(opk_vspace_t* vspace, opk_vector_t *vdst,
         double alpha, const opk_vector_t* vx,
         double beta,  const opk_vector_t* vy,
         double gamma, const opk_vector_t* vz)
{
  /* Note: we already know that neither ALPHA nor BETA nor GAMMA is 0. */
  const REAL* x = DATA(vx);
  const REAL* y = DATA(vy);
  const REAL* z = DATA(vz);
  REAL* dst = DATA(vdst);
  opk_index_t j, n = vspace->size;
#if SINGLE_PRECISION
  REAL ALPHA = (REAL)alpha;
  REAL BETA  = (REAL)beta;
  REAL GAMMA = (REAL)gamma;
#endif
  for (j = 0; j < n; ++j) {
    dst[j] = ALPHA*x[j] + BETA*y[j] + GAMMA*z[j];
  }
}

#define NEW_VECTOR_SPACE OPK_JOIN3(opk_new_simple_, REAL, _vector_space)
#define WRAP_VECTOR OPK_JOIN3(opk_wrap_simple_, REAL, _vector)

#if SINGLE_PRECISION
#  define NOUN "single"
#else
#  define NOUN "double"
#endif

static const char* ident = "simple vector space for " NOUN " precision floating point values";

opk_vspace_t*
NEW_VECTOR_SPACE(opk_index_t size)
{
  opk_vspace_t* vspace;

  vspace = opk_allocate_vector_space(ident, size, 0);
  if (vspace != NULL) {
    vspace->finalize = finalize;
    vspace->create = create;
    vspace->delete = delete;
    vspace->fill = fill;
    vspace->norm1 = norm1;
    vspace->norm2 = norm2;
    vspace->norminf = norminf;
    vspace->dot = dot;
    vspace->copy = copy;
    vspace->swap = swap;
    vspace->scale = scale;
    vspace->axpby = axpby;
    vspace->axpbypcz = axpbypcz;
  }
  return vspace;
}

/* Wrap existing data into a simple vector.  The caller is responsible of
   releasing the data when no longer needed and of ensuring that the memory is
   sufficiently large and correctly aligned. */
opk_vector_t*
WRAP_VECTOR(opk_vspace_t* vspace, REAL data[])
{
  opk_vector_t* v;
  if (vspace->ident != ident) {
    errno = EINVAL;
    return NULL;
  }
  if (data == NULL) {
    errno = EFAULT;
    return NULL;
  }
  v = opk_valloc(vspace, sizeof(simple_vector_t));
  if (v != NULL) {
    DATA(v) = data;
  }
  return v;
}

/*
 * Local Variables:
 * mode: C
 * tab-width: 8
 * c-basic-offset: 2
 * fill-column: 79
 * coding: utf-8
 * End:
 */