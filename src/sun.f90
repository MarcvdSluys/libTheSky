!> \file sun.f90  Procedures that calculate a low-accuracy position of the Sun for libTheSky


!  Copyright (c) 2002-2023  Marc van der Sluys - marc.vandersluys.nl
!   
!  This file is part of the libTheSky package, 
!  see: http://libthesky.sf.net/
!  
!  This is free software: you can redistribute it and/or modify it under the terms of the
!  European Union Public Licence 1.2 (EUPL 1.2).
!  
!  This software is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
!  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
!  See the EU Public Licence for more details.
!  
!  You should have received a copy of the European Union Public Licence along with this code.
!  If not, see <https://www.eupl.eu/1.2/en/>.


!***********************************************************************************************************************************
!> \brief Low-accuracy procedures for the Sun

module TheSky_sun
  implicit none
  save
  
contains
  
  
  !*********************************************************************************************************************************
  !> \brief  Low-accuracy solar coordinates
  !!
  !! \param jd    Julian Day of computation
  !! \param calc  Calculate:  1: l,b,r,  2: & ra,dec,  3: & gmst,agst,  4: & az,alt,  5: & mag + p.a.,  99: & topo alt + refraction
  !!
  !! \param lat   Latitude of the observer (rad, optional)
  !! \param lon   Longitude of the observer (rad, optional)
  !!
  !!
  !! \note
  !! - accuracy: ~0.01°;  ~0.0033° when comparing ecliptical coordinates to VSOP87 for 1900-2100 (10^5 random instances)
  !! - for 1900-2100, the terms greater than Tjc^2 can be neglected without loss of accuracy
  !! 
  !! \note
  !! - lat0 and lon0 can be provided through the module TheSky_local (rad, rad), or through the optional arguments.
  !!   Note that using the latter will update the former!
  !! - results are returned in the array planpos() in the module TheSky_planetdata
  !!
  !! \see
  !! - Chapront-Touze, Chapront, A&A, 190, p.342, 1988, Table 6 (CTC88)
  !! - Explanatory Supplement to the Astronimical Almanac (3rd Ed, 2012)
  !! - Meeus, Astronomical Algorithms, 1998, Ch.25
  !! - Simon et al, A&A, 282, p.663 (1994)
  !! 
  !! \todo  odot is off by ~10" (~0.003d) in Meeus, Example 25a.  Would need better L0 or C (or M?)
  
  subroutine sunpos_la(jd, calc, lat,lon)
    use SUFR_kinds, only: double
    use SUFR_constants, only: jd2000, au, earthr,rsun
    use SUFR_angles, only: rev
    
    use TheSky_planetdata, only: planpos
    use TheSky_coordinates, only: eq2horiz, refract
    use TheSky_datetime, only: calc_deltat, calc_gmst
    use TheSky_local, only: lon0,lat0
    
    implicit none
    real(double), intent(in) :: jd
    integer, intent(in) :: calc
    real(double), intent(in), optional :: lat,lon
    
    real(double) :: jde,deltat,tjc,tjc2,tjc3,tjc4, Aorb, l0,m,e,c,odot,nu,omg,a1e2,r, aber, lam,b
    real(double) :: ra,dec,lm,eps,eps0,deps,gmst,agst,lst,dpsi,az,alt,hh, llat,llon
    
    ! Handle optional variables:
    llat = lat0
    llon = lon0
    if(present(lat)) llat = lat
    if(present(lon)) llon = lon
    
    deltat = calc_deltat(jd)
    jde    = jd + deltat/86400.d0
    !tjc    = (jde-jd2000)/36525.d0    ! Julian Centuries after 2000.0 in dynamical time
    tjc    = (jd-jd2000)/36525.d0     ! Julian Centuries after 2000.0;  JD compares better to VSOP87 than JDE (~7% for 1900-2100)
    tjc2   = tjc*tjc                  ! T^2                             In fact JD - DeltaT compares even better(!) (~4%)
    tjc3   = tjc2*tjc                 ! T^3
    tjc4   = tjc2*tjc2                ! T^4
    
    Aorb = 1.0000010178d0  ! Semi-major axis of the Earth's orbit (Simon et al, 1994)
    
    ! Sun's mean longitude, Simon et al, 5.9.3:
    l0 = 4.895063113086d0 + 628.331965406500135d0 *tjc + 5.29213354358d-6 *tjc2 + 3.4940522d-10 *tjc3 - &
         1.1407666d-10 *tjc4 - 8.726646d-14 *tjc4*tjc + 9.696d-16 * tjc4*tjc2
    
    ! Sun's mean anomaly, l' in CTC88:
    m  = 6.24006012697d0 + 628.3019551680d0*tjc - 2.680535d-6*tjc2  + 7.12676d-10*tjc3
    
    ! Eccentricity of the Earth's orbit, Simon et al, 5.9.3:
    e  = 0.0167086342d0 - 4.203654d-5 *tjc - 1.26734d-7 *tjc2  + 1.444d-10*tjc3 - 2.d-14*tjc4 + 3.d-15*tjc4*tjc
    
    ! Sun's equation of the centre := true - mean anomaly - https://en.wikipedia.org/wiki/Equation_of_the_center:
    c = (2*e - 0.25d0*e**3)*sin(m) + 1.25d0*e**2*sin(2*m) + 13.d0/12.d0*e**3*sin(3*m)  ! Brown, 1896, Chap. III, Eq.7, up to e^3,
    !                                                                       and Expl. Supl. t.t. Astronimical Almanac 3rd Ed, Eq.9.1
    !c = (2*e - 0.25d0*e**3)*sin(m) + (1.25d0*e**2 - 11.d0/24.d0*e**4)*sin(2*m) + 13.d0/12.d0*e**3*sin(3*m) &
    !     + 103.d0/96.d0*e**4*sin(4*m) ! Brown, 1896, Chap. III, Eq.7, up to e^4
    
    odot = l0 + c  ! True longitude
    nu = m + c     ! True anomaly
    
    a1e2 = Aorb*(1.d0-e**2)  ! a(1-e^2)
    r = a1e2/(1.d0 + e*cos(nu))  ! Heliocentric distance of the Earth / geocentric dist. of the Sun, Eq. 25.5
    
    ! Longitude of the Moon's mean ascending node, CTC88:
    omg  = 2.18243919722d0  -  33.7570446083d0 *tjc  +  3.623594d-5 *tjc2  +  3.734035d-8 *tjc3  -  2.87931d-10 *tjc4
    
    ! Mean longitude of the Moon, L in CTC88:
    lm   = 3.810344430588d0  +  8399.709113522267d0*tjc  -  2.315615585d-5*tjc2  +  3.23904d-8*tjc3  -  2.67714d-10*tjc4
    !lm  = 3.8103408236d0    +  8399.7091116339958d0*tjc -  2.755176757d-5*tjc2  +  3.239043d-8*tjc3 -  2.6771d-10*tjc4 - Meeus, CHECK 3rd term!
     
    ! Nutation in longitude, 1980 IAU Theory of Nutation, Seidelmann (1982), Table I, lines 1,9,31,2,10 -> rad:
    dpsi = (-8.338601d-5-7.1365d-8*tjc)*sin(omg) - 6.39324d-6*sin(2*l0) - 1.1025d-6*sin(2*lm) + 9.9969d-7*sin(2*omg) &
         + 6.9134d-7*sin(m)
    
    ! Annual abberation = k * a(1-e^2)/r, Kovalevsky and Seidelmann, Fundamentals of Astrometry (2004):
    aber = -9.9365085d-5 * a1e2/r
    
    ! Apparent geocentric longitude and latitude, referred to the true equinox of date:
    lam  = rev(odot + aber + dpsi)
    b    = 0.d0
    
    
    planpos(1)  = lam  ! Geocentric longitude
    planpos(2)  = b    ! Geocentric latitude
    planpos(3)  = r    ! Geocentric distance
    planpos(4)  = r    ! Geocentric distance
    
    ! Secondary variables, (almost) for free:
    planpos(7)  = 5.77551830441d-3 * r    ! Light time in days
    planpos(11) = 0.d0                    ! Elongation
    planpos(12) = 2*rsun/(r*au)           ! Apparent diameter
    planpos(13) = -26.73d0                ! Apparent magnitude
    planpos(14) = 1.d0                    ! Illuminated fraction
    planpos(15) = 0.d0                    ! Phase angle
    planpos(17) = asin(earthr/(r*au))     ! Horizontal parallax
    
    planpos(40) = jde                     ! JD
    planpos(41:43) = planpos(1:3)         ! Geocentric, "true" L,B,R of the Sun
    planpos(46) = tjc                     ! App. dyn. time in Julian Centuries since 2000.0
    
    if(calc.eq.1) return
    
    
    
    ! Obliquity of the ecliptic and nutation:
    eps0 = 0.409092804222d0 - 2.26965525d-4*tjc - 2.86d-9*tjc2 + 8.78967d-9*tjc3           ! Mean obliq. o.t. eclip  (Lieske et al, 1977)
    deps = 4.46d-5*cos(omg) + 2.76d-6*cos(2*l0) + 4.848d-7*cos(2*lm) - 4.36d-7*cos(2*omg)  ! Nutation in obliquity, Meeus, p.144
    eps  = eps0 + deps                                                                     ! True obliquity of the ecliptic
    
    ra   = atan2(cos(eps)*sin(lam),cos(lam))  ! Geocentric right ascension, Eq. 25.6
    dec  = asin(sin(eps)*sin(lam))            ! Geocentric declination,     Eq. 25.7
    
    
    planpos(5)  = ra    ! Geocentric right ascension
    planpos(6)  = dec   ! Geocentric declination
    planpos(47) = dpsi  ! Nutation in longitude
    planpos(48) = eps   ! True obliquity of the ecliptic; corrected for nutation
    planpos(50) = eps0  ! Mean obliquity of the ecliptic; without nutation
    
    if(calc.eq.2) return
    
    
    
    gmst = calc_gmst(jd)              ! Greenwich mean sidereal time
    agst = rev(gmst + dpsi*cos(eps))  ! Correction for equation of the equinoxes -> Gr. apparent sid. time
    lst  = rev(agst + llon)           ! Local apparent sidereal time, llon > 0 for E
    
    planpos(44) = lst                 ! Local APPARENT sidereal time
    planpos(45) = rev(agst)           ! Greenwich mean sidereal time
    planpos(49) = rev(gmst)           ! Correction for equation of the equinoxes -> Gr. apparent sid. time
    
    if(calc.eq.3) return
    
    
    
    call eq2horiz(ra,dec,agst, hh,az,alt, lat=llat,lon=llon)
    planpos(8)  = rev(hh)  ! Geocentric hour angle
    planpos(9)  = rev(az)  ! Geocentric azimuth
    planpos(10) = alt      ! Geocentric altitude
    
    if(calc.eq.4) return
    
    
    planpos(13) = sunmagn(r)                                            ! Apparent magnitude
    planpos(16) = atan2(sin(hh),tan(llat)*cos(dec) - sin(dec)*cos(hh))  ! Parallactic angle
    
    if(calc.eq.5) return
    
    ! calc = 99:
    planpos(29) = planpos(9)                             ! topocentric azimuth ~ geocentric azimuth
    planpos(30) = alt - asin(sin(planpos(17))*cos(alt))  ! alt' = alt - Hp*cos(alt); topocentric altitude
    planpos(31) = planpos(30) + refract(planpos(30))     ! Topocentric altitude, corrected for atmospheric refraction
    
  end subroutine sunpos_la
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> Compute the position of the Sun - very low accuracy routine (~0.18 degrees in az/alt)
  !!
  !! \param  DoY        Day of year
  !! \param  hour       Hour of day
  !!
  !! \param  lon        Geographic longitunde (radians; >0=east)
  !! \param  lat        Geographic latitunde (radians; >0=north)
  !! \param  tz         Time zone (hours; >0=east)
  !!
  !! \param ha         Hour angle of the Sun (radians) (output)
  !! \param dec        Declination of the Sun (radians; >0=north) (output)
  !!
  !! \param az         Azimuth of the Sun (radians; 0=north, pi/2=east) (output)
  !! \param alt        Altitude of the Sun (radians; >0 = up) (output)
  !!
  !! \see Wenham, S.R.: Applied photovoltaics (2012; book), Appendix B
  
  subroutine sunpos_vla(DoY,hour, lon,lat,tz, ha,dec, az,alt)
    use SUFR_kinds, only: double
    use SUFR_constants, only: pi2, h2r,r2h
    
    implicit none
    integer, intent(in) :: DoY
    real(double), intent(in) :: hour, lon,lat,tz
    real(double), intent(out) :: dec,ha, alt,az
    real(double) :: eclon, Teq,Tdif,Tsol
    
    ! Declination of the Sun:
    eclon = pi2/365.d0 * DoY  ! indication of the ecliptic longitude of the Sun (rad)
    
    dec = 5.80863d-3 - 0.401146d0 * cos(eclon) - 6.1069d-3  * cos(2 * eclon) - 2.43997d-3 * cos(3 * eclon) &
         +             6.52264d-2 * sin(eclon) + 5.59378d-4 * sin(2 * eclon) + 1.25437d-3 * sin(3 * eclon)    ! Declination (rad)
    ! Note: both 0.066099 and 0.065226 occur in the literature (as 3.7872 and 3.7372 degrees), but without any reference to an 
    ! original paper. 0.065226 gives a ~2% better declination when compared to VSOP87.
    
    
    ! Equation of time:
    if(DoY .lt. 21) then
       Teq = -2.6d0 - 0.44d0 * DoY
    else if(DoY .lt. 136) then
       Teq = -5.2d0 - 9.d0 * cos( (DoY -  43) * 0.0357d0 )
    else if(DoY .lt. 241) then
       Teq = -1.4d0 + 5.d0 * cos( (DoY - 135) * 0.0449d0 )
    else if(DoY .lt. 336) then
       Teq = 6.3d0 + 10.d0 * cos( (DoY - 306) * 0.036d0 )
    else
       Teq = 0.45d0 * (359 - DoY)
    end if
    
    ! Time difference with UT:
    Tdif = tz - lon*r2h - Teq/60.d0  ! tz = Tmet - Tgmt (hours)
    
    ! Solar time:
    Tsol = hour - Tdif  ! (hours)
    
    ! Hour angle of the Sun:
    ha = (Tsol - 12.d0)*h2r  ! (rad)
    
    ! Azimuth of the Sun:
    az = atan2(sin(ha), cos(ha)*sin(lat) - tan(dec)*cos(lat))  ! (rad)
    
    ! Altitude of the Sun:
    alt = asin( sin(dec) * sin(lat)  +  cos(dec) * cos(lat) * cos(ha))  ! (rad)
    
  end subroutine sunpos_vla
  !*********************************************************************************************************************************
  
  
  !*********************************************************************************************************************************
  !> \brief  Calculate Sun magnitude
  !!
  !! \param  dist     Distance (AU)
  !! \retval sunmagn  Sun magnitude
  
  function sunmagn(dist)
    use SUFR_kinds, only: double
    
    implicit none
    real(double), intent(in) :: dist
    real(double) :: sunmagn
    
    sunmagn = -26.74d0 + 5*log10(dist)
  end function sunmagn
  !*********************************************************************************************************************************
  
  
  
  
  
end module TheSky_sun
!***********************************************************************************************************************************
