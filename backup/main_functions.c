/* Copyright (C) 2018  István Bozsó
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <string.h>
#include <stdlib.h>
#include <tgmath.h>
#include <gsl/gsl_matrix_double.h>
#include <gsl/gsl_math.h>
#include <gsl/gsl_linalg.h>
#include <gsl/gsl_blas.h>
#include <gsl/gsl_cblas.h>

#include "main_functions.h"
#include "matrix.h"
#include "aux_macros.h"

#define min_arg 2
#define BUFSIZE 10

/************************
 * Auxilliary functions *
 * **********************/

static void ell_cart (cdouble lon, cdouble lat, cdouble h,
                      double *x, double *y, double *z)
{
    /* From ellipsoidal to cartesian coordinates. */
    
    double n = WA / sqrt(1.0 - E2 * sin(lat) * sin(lat));;

    *x = (              n + h) * cos(lat) * cos(lon);
    *y = (              n + h) * cos(lat) * sin(lon);
    *z = ( (1.0 - E2) * n + h) * sin(lat);

} // end of ell_cart

static void cart_ell (cdouble x, cdouble y, cdouble z,
                      double *lon, double *lat, double *h)
{
    /* From cartesian to ellipsoidal coordinates. */
    
    double n, p, o, so, co;

    n = (WA * WA - WB * WB);
    p = sqrt(x * x + y * y);

    o = atan(WA / p / WB * z);
    so = sin(o); co = cos(o);
    o = atan( (z + n / WB * so * so * so) / (p - n / WA * co * co * co) );
    so = sin(o); co = cos(o);
    n= WA * WA / sqrt(WA * co * co * WA + WB * so * so * WB);

    *lat = o;
    
    o = atan(y/x); if(x < 0.0) o += M_PI;
    *lon = o;
    *h = p / co - n;
}
// end of cart_ell

static void calc_pos(const orbit_fit * orb, double time, cart * pos)
{
    /* Calculate satellite position based on fitted polynomial orbits
     * at `time`. */
    
    uint n_poly   = orb->deg + 1,
         deg      = orb->deg;
    double x = 0.0, y = 0.0, z = 0.0;
    
    cdouble *coeffs = orb->coeffs;
    
    if(n_poly == 2) {
        x = coeffs[0] + coeffs[1] * time;
        y = coeffs[2] + coeffs[3] * time;
        z = coeffs[4] + coeffs[5] * time;
    }
    else {
        // highest degree
        x = coeffs[           + deg] * time;
        y = coeffs[    n_poly + deg] * time;
        z = coeffs[2 * n_poly + deg] * time;
        
        for(uint ii = deg - 1; ii >= 1; ii--) {
            x = (x + coeffs[             ii]) * time;
            y = (y + coeffs[    n_poly + ii]) * time;
            z = (z + coeffs[2 * n_poly + ii]) * time;
        }
        
        // lowest degree
        x += coeffs[         0];
        y += coeffs[    n_poly];
        z += coeffs[2 * n_poly];
    }
    
    if (orb->centered) {
        pos->x = x + orb->coords_mean[0];
        pos->y = y + orb->coords_mean[1];
        pos->z = z + orb->coords_mean[2];
    }
    else {
        pos->x = x;
        pos->y = y;
        pos->z = z;
    }
} // end calc_pos

static double dot_product(const orbit_fit * orb, cdouble X, cdouble Y,
                          cdouble Z, double time)
{
    /* Calculate dot product between satellite velocity vector and
     * and vector between ground position and satellite position. */
    
    double dx, dy, dz, sat_x = 0.0, sat_y = 0.0, sat_z = 0.0,
                       vel_x, vel_y, vel_z, power, inorm;
    uint n_poly = orb->deg + 1,
         deg = orb->deg;
    
    cdouble *coeffs = orb->coeffs;
    
    // linear case 
    if(n_poly == 2) {
        sat_x = coeffs[0] + coeffs[1] * time;
        sat_y = coeffs[2] + coeffs[3] * time;
        sat_z = coeffs[4] + coeffs[5] * time;
        
        vel_x = coeffs[1]; vel_y = coeffs[3]; vel_z = coeffs[5];
    }
    // evaluation of polynom with Horner's method
    else {
        // highest degree
        sat_x = coeffs[           + deg] * time;
        sat_y = coeffs[    n_poly + deg] * time;
        sat_z = coeffs[2 * n_poly + deg] * time;

        for(uint ii = deg - 1; ii >= 1; ii--) {
            sat_x = (sat_x + coeffs[             ii]) * time;
            sat_y = (sat_y + coeffs[    n_poly + ii]) * time;
            sat_z = (sat_z + coeffs[2 * n_poly + ii]) * time;
        }
        
        // lowest degree
        sat_x += coeffs[         0];
        sat_y += coeffs[    n_poly];
        sat_z += coeffs[2 * n_poly];
        
        // constant term
        vel_x = coeffs[1             ];
        vel_y = coeffs[1 +     n_poly];
        vel_z = coeffs[1 + 2 * n_poly];
        
        // linear term
        vel_x += coeffs[2             ] * time;
        vel_y += coeffs[2 +     n_poly] * time;
        vel_z += coeffs[2 + 2 * n_poly] * time;
        
        FOR(ii, 3, n_poly) {
            power = (double) ii - 1;
            vel_x += ii * coeffs[             ii] * pow(time, power);
            vel_y += ii * coeffs[    n_poly + ii] * pow(time, power);
            vel_z += ii * coeffs[2 * n_poly + ii] * pow(time, power);
        }
    }

    if (orb->centered) {
        sat_x += orb->coords_mean[0];
        sat_y += orb->coords_mean[1];
        sat_z += orb->coords_mean[2];
    }

    // satellite coordinates - GNSS coordinates
    dx = sat_x - X;
    dy = sat_y - Y;
    dz = sat_z - Z;
    
    // product of inverse norms
    inorm = (1.0 / norm(dx, dy, dz)) * (1.0 / norm(vel_x, vel_y, vel_z));
    
    // scalar product of delta vector and velocities
    return (vel_x * dx  + vel_y * dy  + vel_z * dz) * inorm;
}
// end dot_product

static void closest_appr(const orbit_fit * orb, cdouble X, cdouble Y,
                         cdouble Z, const uint max_iter, cart * sat_pos)
{
    /* Compute the sat position using closest approche. */
    
    // first, last and middle time
    double t_min = orb->t_min,
           t_max = orb->t_max,
           t_middle;
    
    if (orb->centered) {
        t_min -= orb->t_mean;
        t_max -= orb->t_mean;
    }
    
    // dot products
    double dot_start, dot_middle = 1.0;

    // iteration counter
    uint itr = 0;
    
    dot_start = dot_product(orb, X, Y, Z, t_min);
    
    while (fabs(dot_middle) > 1.0e-11 && itr < max_iter) {
        t_middle = (t_min + t_max) / 2.0;

        dot_middle = dot_product(orb, X, Y, Z, t_middle);
        
        // change start for middle
        if ((dot_start * dot_middle) > 0.0) {
            t_min = t_middle;
            dot_start = dot_middle;
        }
        // change  end  for middle
        else
            t_max = t_middle;

        itr++;
    }
    
    // calculate satellite position at middle time
    calc_pos(orb, t_middle, sat_pos);
} // end closest_appr

static inline void calc_azi_inc(const orbit_fit * orb,
                                cdouble X, cdouble Y, cdouble Z,
                                cdouble lon, cdouble lat,
                                const uint max_iter, double * azi,
                                double * inc)
{
    double xf, yf, zf, xl, yl, zl, t0, temp_azi;
    cart sat;
    // satellite closest approache cooridantes
    closest_appr(orb, X, Y, Z, max_iter, &sat);
    
    xf = sat.x - X;
    yf = sat.y - Y;
    zf = sat.z - Z;
    
    // estiamtion of azimuth and inclination
    xl = - sin(lat) * cos(lon) * xf
         - sin(lat) * sin(lon) * yf + cos(lat) * zf ;
    
    yl = - sin(lon) * xf + cos(lon) * yf;
    
    zl = + cos(lat) * cos(lon) * xf
         + cos(lat) * sin(lon) * yf + sin(lat) * zf ;
    
    t0 = norm(xl, yl, zl);
    
    *inc = acos(zl / t0) * RAD2DEG;
    
    if(xl == 0.0) xl = 0.000000001;
    
    temp_azi = atan(fabs(yl / xl));
    
    if( (xl < 0.0) && (yl > 0.0) ) temp_azi = M_PI - temp_azi;
    if( (xl < 0.0) && (yl < 0.0) ) temp_azi = M_PI + temp_azi;
    if( (xl > 0.0) && (yl < 0.0) ) temp_azi = 2.0 * M_PI - temp_azi;
    
    temp_azi *= RAD2DEG;
    
    if(temp_azi > 180.0)
        temp_azi -= 180.0;
    else
        temp_azi += 180.0;
    
    *azi = temp_azi;
}


/***********************************************
 * Main functions - calleble from command line *
 ***********************************************/

int fit_orbit(int argc, char **argv)
{
    int error = err_succes;
    
    aux_checkarg(4,
    "\n Usage: inmet fit_orbit [coords] [deg] [is_centered] [fit_file]\
     \n \
     \n coords      - (ascii, in) file with (t,x,y,z) coordinates\
     \n deg         - degree of fitted polynom\
     \n is_centered - 1 = subtract mean time and coordinates from time points and \
     \n               coordinates, 0 = no centering\
     \n fit_file    - (ascii, out) contains fitted orbit polynom parameters\
     \n\n");

    FILE *incoords, *fit_file;
    uint deg = (uint) atoi(argv[3]);
    uint is_centered = (uint) atoi(argv[4]);
    uint idx = 0, ndata = 0;
    uint max_idx = BUFSIZE - 1;
    
    double residual[] = {0.0, 0.0, 0.0};

    aux_open(incoords, argv[2], "r");
    
    orbit * orbits;
    aux_malloc(orbits, orbit, BUFSIZE);
    
    double t_mean = 0.0,  // mean value of times
           t, x, y, z,    // temp storage variables
           x_mean = 0.0,  // x, y, z mean values
           y_mean = 0.0,
           z_mean = 0.0,
           t_min, t_max, res_tmp;
    
    gsl_vector *tau, // vector for QR decompisition
               *res; // vector for holding residual values
    
    // matrices
    gsl_matrix *design, *obs, *fit;
    
    // vector views of matrix columns and rows
    gsl_vector_view fit_view;
    
    if (is_centered) {
        while(fscanf(incoords, "%lf %lf %lf %lf\n", &t, &x, &y, &z) > 0) {
            ndata++;
            
            t_mean += t;
            x_mean += x;
            y_mean += y;
            z_mean += z;
            
            orbits[idx].t = t;
            orbits[idx].x = x;
            orbits[idx].y = y;
            orbits[idx].z = z;

            idx++;
            
            if (idx >= max_idx) {
                aux_realloc(orbits, orbit, 2 * idx);
                max_idx = 2 * idx - 1;
            }
        }

        // calculate means
        t_mean /= (double) ndata;
    
        x_mean /= (double) ndata;
        y_mean /= (double) ndata;
        z_mean /= (double) ndata;
    }
    else {
        while(fscanf(incoords, "%lf %lf %lf %lf\n",
                     &orbits[idx].t, &orbits[idx].x, &orbits[idx].y,
                     &orbits[idx].z) > 0) {
            idx++;
            ndata++;
            
            if (idx >= max_idx) {
                aux_realloc(orbits, orbit, 2 * idx);
                max_idx = 2 * idx - 1;
            }
        }
    }
    
    t_min = orbits[0].t;
    
    FOR(ii, 1, ndata) {
        t = orbits[ii].t;
        
        if (t < t_min)
            t_min = t;
    }

    t_max = orbits[0].t;

    FOR(ii, 1, ndata) {
        t = orbits[ii].t;
        
        if (t > t_max)
            t_max = t;
    }
    
    if (ndata < (deg + 1)) {
        errorln("Underdetermined system, we have less data points (%d) than\
                 \nunknowns (%d)!", ndata, deg + 1);
        error = err_num;
        goto fail;
    }

    obs = gsl_matrix_alloc(ndata, 3);
    fit = gsl_matrix_alloc(3, deg + 1);

    design = gsl_matrix_alloc(ndata, deg + 1);
    
    tau = gsl_vector_alloc(deg + 1);
    res = gsl_vector_alloc(ndata);
    
    FOR(ii, 0, ndata) {
        // fill up matrix that contains coordinate values
        Mset(obs, ii, 0, orbits[ii].x - x_mean);
        Mset(obs, ii, 1, orbits[ii].y - y_mean);
        Mset(obs, ii, 2, orbits[ii].z - z_mean);
        
        t = orbits[ii].t - t_mean;
        
        // fill up design matrix
        
        // first column is ones
        Mset(design, ii, 0, 1.0);
        
        // second column is t values
        Mset(design, ii, 1, t);
        
        // further columns contain the power of t values
        FOR(jj, 2, deg + 1)
            *Mptr(design, ii, jj) = Mget(design, ii, jj - 1) * t;
    }

    free(orbits); orbits = NULL;
    
    // factorize design matrix
    if (gsl_linalg_QR_decomp(design, tau)) {
        error("QR decomposition failed.\n");
        error = err_num;
        goto fail;
    }
    
    // do the fit for x, y, z
    FOR(ii, 0, 3) {
        fit_view = gsl_matrix_row(fit, ii);
        gsl_vector_const_view coord = gsl_matrix_const_column(obs, ii);
        
        if (gsl_linalg_QR_lssolve(design, tau, &coord.vector, &fit_view.vector,
                                  res)) {
            error("Solving of linear system failed!\n");
            error = err_num;
            goto fail;
        }
        
        res_tmp = 0.0;
        
        // calculate RMS of residual values
        FOR(jj, 0, ndata)
            res_tmp += Vget(res, jj) * Vget(res, jj);
        
        residual[ii] = sqrt(res_tmp / ndata);
    }
    
    aux_open(fit_file, argv[5], "w");
    
    fprintf(fit_file, "centered: %u\n", is_centered);
    
    if (is_centered) {
        fprintf(fit_file, "t_mean: %lf\n", t_mean);
        fprintf(fit_file, "coords_mean: %lf %lf %lf\n",
                                        x_mean, y_mean, z_mean);
    }
    
    fprintf(fit_file, "t_min: %lf\n", t_min);
    fprintf(fit_file, "t_max: %lf\n", t_max);
    fprintf(fit_file, "deg: %u\n", deg);
    fprintf(fit_file, "coeffs: ");
    
    FOR(ii, 0, 3)
        FOR(jj, 0, deg + 1)
            fprintf(fit_file, "%lf ", Mget(fit, ii, jj));

    fprintf(fit_file, "\nRMS of residuals (x, y, z) [m]: (%lf, %lf, %lf)\n",
                      residual[0], residual[1], residual[2]);
    
    fprintf(fit_file, "\n");
    
    gsl_matrix_free(design);
    gsl_matrix_free(obs);
    gsl_matrix_free(fit);
    
    gsl_vector_free(tau);
    gsl_vector_free(res);
        
    fclose(incoords);
    fclose(fit_file);
    
    return error;

fail:
    gsl_matrix_free(design);
    gsl_matrix_free(obs);
    gsl_matrix_free(fit);
    
    gsl_vector_free(tau);
    gsl_vector_free(res);
    
    aux_free(orbits);
    
    aux_close(incoords);
    aux_close(fit_file);
    
    return error;
}


int eval_orbit(int argc, char **argv)
{
    int error = err_succes;

    aux_checkarg(4,
    "\n Usage: inmet eval_orbit [fit_file] [steps] [multiply] [outfile]\
     \n \
     \n fit_file    - (ascii, in) contains fitted orbit polynom parameters\
     \n nstep       - evaluate x, y, z coordinates at nstep number of steps\
     \n               between the range of t_min and t_max\
     \n multiply    - calculated coordinate values will be multiplied by this number\
     \n outfile     - (ascii, out) coordinates and time values will be written \
     \n               to this file\
     \n\n");

    FILE *outfile;
    orbit_fit orb;
    double t_min, t_mean, dstep, t, nstep, mult =  atof(argv[4]);
    cart pos;
    
    if ((error = read_fit(argv[2], &orb))) {
        errorln("Could not read orbit fit file %s. Exiting!", argv[2]);
        return error;
    }
    
    t_min = orb.t_min;
    nstep = atof(argv[3]);
    
    dstep = (orb.t_max - t_min) / nstep;
    
    aux_open(outfile, argv[5], "w");
    
    if (orb.centered)
        t_mean = orb.t_mean;
    else
        t_mean = 0.0;

    FOR(ii, 0, ((uint) nstep) + 1) {
        t = t_min - t_mean + ii * dstep;
        calc_pos(&orb, t, &pos);
        fprintf(outfile, "%lf %lf %lf %lf\n", t + t_mean, pos.x * mult,
                                                          pos.y * mult,
                                                          pos.z * mult);
    }

    fclose(outfile);
    return error;

fail:
    aux_close(outfile);
    return error;
}

int azi_inc(int argc, char **argv)
{
    int error = err_succes;
    
    aux_checkarg(5,
    "\n Usage: inmet azi_inc [fit_file] [coords] [mode] [max_iter] [outfile]\
     \n \
     \n fit_file - (ascii, in) contains fitted orbit polynom parameters\
     \n coords   - (binary, in) inputfile with coordinates\
     \n mode     - xyz for WGS-84 coordinates, llh for WGS-84 lon., lat., height\
     \n max_iter - maximum number of iterations when calculating closest approache\
     \n outfile  - (binary, out) azi, inc pairs will be printed to this file\
     \n\n");

    FILE *infile, *outfile;
    uint is_lonlat, max_iter = atoi(argv[5]);
    double coords[3];
    orbit_fit orb;

    // topocentric parameters in PS local system
    double X, Y, Z,
           lon, lat, h,
           azi, inc;
    
    if ((error = read_fit(argv[2], &orb))) {
        errorln("Could not read orbit fit file %s. Exiting!", argv[2]);
        return error;
    }
    
    aux_open(infile, argv[3], "rb");
    aux_open(outfile, argv[6], "wb");
    
    // infile contains lon, lat, h
    if (str_isequal(argv[4], "llh")) {
        while (fread(coords, sizeof(double), 3, infile) > 0) {
            lon = coords[0] * DEG2RAD;
            lat = coords[1] * DEG2RAD;
            h   = coords[2];
            
            // calulate surface WGS-84 Cartesian coordinates
            ell_cart(lon, lat, h, &X, &Y, &Z);
            
            calc_azi_inc(&orb, X, Y, Z, lon, lat, max_iter, &azi, &inc);

            fwrite(&azi, sizeof(double), 1, outfile);
            fwrite(&inc, sizeof(double), 1, outfile);
        } // end while
    }
    // infile contains X, Y, Z
    else if (str_isequal(argv[4], "xyz")) {
        while (fread(coords, sizeof(double), 3, infile) > 0) {
            
            // calulate surface WGS-84 Cartesian coordinates
            ell_cart(lon, lat, h, &coords[0], &coords[1], &coords[2]);
            
            calc_azi_inc(&orb, coords[0], coords[1], coords[2],
                         lon, lat, max_iter, &azi, &inc);
            
            fwrite(&azi, sizeof(double), 1, outfile);
            fwrite(&inc, sizeof(double), 1, outfile);
        } // end while
    } // end else if
    else {
        errorln("Third argument should be either llh or xyz not %s!",
                argv[4]);
        error = err_arg;
        goto fail;
    }

    fclose(infile);
    fclose(outfile);
    return error;

fail:
    aux_close(infile);
    aux_close(outfile);
    return error;
}

#if 1

#define SIZE 2500

int test_matrix1(void)
{
    matrix * mtx1, *mtx2, *mtx3;
    mtx_double(mtx1, SIZE, SIZE);
    mtx_double(mtx2, SIZE, SIZE);
    mtx_double(mtx3, SIZE, SIZE);
    
    FOR(ii, 0, SIZE) {
        FOR(jj, 0, SIZE) {
            dmtx(mtx1, ii, jj) = (double) ii + jj;
            dmtx(mtx2, ii, jj) = (double) jj + ii;
        }
    }

    cblas_dgemm(CblasRowMajor, CblasTrans, CblasTrans, SIZE, SIZE, SIZE, 1.0, (double *)mtx1->data, SIZE, (double *)mtx2->data, SIZE, 0.0, (double *)mtx3->data, SIZE);

    FOR(ii, 0, 10)
        printf("%lf ", dmtx(mtx3, 0, ii));
    
    printf("\n");

    
    mtx_free(mtx1);
    mtx_free(mtx2);
    mtx_free(mtx3);
    return 0;
fail:
    mtx_safe_free(mtx1);
    mtx_safe_free(mtx2);
    mtx_safe_free(mtx3);
    return 1;
}

int test_matrix2(void)
{
    
    gsl_matrix * mtx1 = gsl_matrix_alloc(SIZE, SIZE);
    gsl_matrix * mtx2 = gsl_matrix_alloc(SIZE, SIZE);
    gsl_matrix * mtx3 = gsl_matrix_alloc(SIZE, SIZE);
    
    FOR(ii, 0, SIZE) {
        FOR(jj, 0, SIZE) {
            Mset(mtx1, ii, jj, (double) ii + jj);
            Mset(mtx2, ii, jj, (double) jj + ii);
        }
    }
    
    gsl_blas_dgemm(CblasTrans, CblasTrans, 1.0, mtx1, mtx2, 0.0, mtx3);
    
    FOR(ii, 0, 10)
        printf("%lf ", Mget(mtx3, 0, ii));
    
    printf("\n");
    
    gsl_matrix_free(mtx1);
    gsl_matrix_free(mtx2);
    gsl_matrix_free(mtx3);
    return 0;
}

#endif
