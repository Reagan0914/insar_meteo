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

#include <iostream>

//#include <stdio.h>
#include <cmath>

#include "satorbit.hpp"
#include "array.hpp"
#include "utils.hpp"

static void calc_pos(const orbit_fit * orb, double time, cart * pos)
{
    // Calculate satellite position based on fitted polynomial orbits at time
    
    size_t n_poly = orb->deg + 1, is_centered = orb->is_centered;
    double x = 0.0, y = 0.0, z = 0.0;
    
    const double *coeffs = orb->coeffs, *mean_coords = orb->mean_coords;
    
    if (is_centered)
        time -= orb->mean_t;
    
    if(n_poly == 2) {
        x = coeffs[0] * time + coeffs[1];
        y = coeffs[2] * time + coeffs[3];
        z = coeffs[4] * time + coeffs[5];
    }
    else {
        x = coeffs[0]           * time;
        y = coeffs[n_poly]      * time;
        z = coeffs[2 * n_poly]  * time;

        FOR(ii, 1, n_poly - 1) {
            x = (x + coeffs[             ii]) * time;
            y = (y + coeffs[    n_poly + ii]) * time;
            z = (z + coeffs[2 * n_poly + ii]) * time;
        }
        
        x += coeffs[    n_poly - 1];
        y += coeffs[2 * n_poly - 1];
        z += coeffs[3 * n_poly - 1];
    }
    
    if (is_centered) {
        x += mean_coords[0];
        y += mean_coords[1];
        z += mean_coords[2];
    }
    
    pos->x = x; pos->y = y; pos->z = z;
} // end calc_pos

static double dot_product(const orbit_fit * orb, cdouble X, cdouble Y,
                          cdouble Z, double time)
{
    /* Calculate dot product between satellite velocity vector and
     * and vector between ground position and satellite position. */
    
    double dx, dy, dz, sat_x = 0.0, sat_y = 0.0, sat_z = 0.0,
                       vel_x, vel_y, vel_z, power, inorm;
    size_t n_poly = orb->deg + 1;
    
    const double *coeffs = orb->coeffs, *mean_coords = orb->mean_coords;
    
    if (orb->is_centered)
        time -= orb->mean_t;
    
    // linear case 
    if(n_poly == 2) {
        sat_x = coeffs[0] * time + coeffs[1];
        sat_y = coeffs[2] * time + coeffs[3];
        sat_z = coeffs[4] * time + coeffs[5];
        vel_x = coeffs[0]; vel_y = coeffs[2]; vel_z = coeffs[4];
    }
    // evaluation of polynom with Horner's method
    else {
        
        sat_x = coeffs[0]           * time;
        sat_y = coeffs[n_poly]      * time;
        sat_z = coeffs[2 * n_poly]  * time;

        FOR(ii, 1, n_poly - 1) {
            sat_x = (sat_x + coeffs[             ii]) * time;
            sat_y = (sat_y + coeffs[    n_poly + ii]) * time;
            sat_z = (sat_z + coeffs[2 * n_poly + ii]) * time;
        }
        
        sat_x += coeffs[    n_poly - 1];
        sat_y += coeffs[2 * n_poly - 1];
        sat_z += coeffs[3 * n_poly - 1];
        
        vel_x = coeffs[    n_poly - 2];
        vel_y = coeffs[2 * n_poly - 2];
        vel_z = coeffs[3 * n_poly - 2];
        
        FOR(ii, 0, n_poly - 3) {
            power = (double) n_poly - 1.0 - ii;
            vel_x += ii * coeffs[             ii] * pow(time, power);
            vel_y += ii * coeffs[    n_poly + ii] * pow(time, power);
            vel_z += ii * coeffs[2 * n_poly + ii] * pow(time, power);
        }
    }
    
    if (orb->is_centered) {
        sat_x += mean_coords[0];
        sat_y += mean_coords[1];
        sat_z += mean_coords[2];
    }
    
    // satellite coordinates - GNSS coordinates
    dx = sat_x - X;
    dy = sat_y - Y;
    dz = sat_z - Z;
    
    // product of inverse norms
    inorm = (1.0 / norm(dx, dy, dz)) * (1.0 / norm(vel_x, vel_y, vel_z));
    
    return((vel_x * dx  + vel_y * dy  + vel_z * dz) * inorm);
}
// end dot_product

static void closest_appr(const orbit_fit * orb, cdouble X, cdouble Y,
                         cdouble Z, const size_t max_iter, cart * sat_pos)
{
    // Compute the sat position using closest approche.
    
    // first, last and middle time, extending the time window by 5 seconds
    double t_start = orb->start_t - 5.0,
           t_stop  = orb->stop_t + 5.0,
           t_middle = 0.0;
    
    // dot products
    double dot_start, dot_middle = 1.0;

    // iteration counter
    size_t itr = 0;
    
    dot_start = dot_product(orb, X, Y, Z, t_start);
    
    while( fabs(dot_middle) > 1.0e-11 && itr < max_iter) {
        t_middle = (t_start + t_stop) / 2.0;

        dot_middle = dot_product(orb, X, Y, Z, t_middle);
        
        // change start for middle
        if ((dot_start * dot_middle) > 0.0) {
            t_start = t_middle;
            dot_start = dot_middle;
        }
        // change  end  for middle
        else
            t_stop = t_middle;

        itr++;
    }
    
    // calculate satellite position at middle time
    calc_pos(orb, t_middle, sat_pos);
} // end closest_appr

inline void im_calc_azi_inc(const orbit_fit * orb, cdouble X, cdouble Y,
                            cdouble Z, cdouble lon, cdouble lat,
                            const size_t max_iter, double * azi,
                            double * inc)
{
    double xf, yf, zf, xl, yl, zl, t0;
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
    
    double temp_azi = atan(fabs(yl / xl));
    
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

void calc_azi_inc(double start_t, double stop_t, double mean_t,
                  double * mean_coords, double * coeffs, int is_centered,
                  int deg, int max_iter, int is_lonlat, double * coords,
                  int n_coords, double * azi_inc)
{
    // Set up orbit polynomial structure
    orbit_fit orb = {.mean_t = mean_t, .mean_coords = mean_coords,
                     .start_t = start_t, .stop_t = stop_t,
                     .coeffs = coeffs, .is_centered = (size_t) is_centered,
                     .deg = (size_t) deg};
    
    const size_t ncols = 3;
    const size_t nrows = (size_t) n_coords;
    double X, Y, Z, lon, lat, h;

    // coords contains lon, lat, h
    if (is_lonlat) {
        FOR(ii, 0, nrows) {
            lon = ptr_elem2(coords, ii, 0, ncols) * DEG2RAD;
            lat = ptr_elem2(coords, ii, 1, ncols) * DEG2RAD;
            h   = ptr_elem2(coords, ii, 2, ncols);
            
            // calulate surface WGS-84 Cartesian coordinates
            im_ell_cart(lon, lat, h, &X, &Y, &Z);
            
            im_calc_azi_inc(&orb, X, Y, Z, lon, lat, max_iter, 
                            ptr_ptr2(azi_inc, ii, 0, ncols),
                            ptr_ptr2(azi_inc, ii, 1, ncols));
            
        }
        // end for
    }
    // coords contains X, Y, Z
    else {
        FOR(ii, 0, nrows) {
            X = ptr_elem2(coords, ii, 0, ncols);
            Y = ptr_elem2(coords, ii, 1, ncols);
            Z = ptr_elem2(coords, ii, 2, ncols);
            
            // calulate surface WGS-84 geodetic coordinates
            im_cart_ell(X, Y, Z, &lon, &lat, &h);
        
            im_calc_azi_inc(&orb, X, Y, Z, lon, lat, max_iter, 
                            ptr_ptr2(azi_inc, ii, 0, ncols),
                            ptr_ptr2(azi_inc, ii, 1, ncols));
        }
        // end for
    }
    // end else
}

using namespace std;

// Functions to be exported to Python need to be callable from C

extern "C" {

void test(double * _array, int n, int m)
{
    int tmp[2] = {n, m};
    array<double, 2> arr(_array, tmp);
    
    FOR(ii, 0, arr.get_rows()) {
        FOR(jj, 0, arr.get_cols())
            cout << arr(ii,jj) << " ";
        cout << endl;
    }
    
    //ar_double array;
    
    //cout << norm(1.0, 2.0, 3.0) << endl;
    //cout << norm(1, 2, 3) << endl;
}

}
// end extern "C"