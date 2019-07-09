using Plots


"""
`phantom = ellipsoid_im(ig, params;
    oversample=1, checkfov=false, how=:slow, showmem=false, hu_scale=1, return_params=false)`

generate ellipsoid phantom image from parameters:
    `[x_center, y_center, z_center, x_radius, y_radius, z_radius,
        xy_angle_degrees, z_angle_degrees, density]`

in
* `ig`            image_geom()
* `params`        `[9 N]` ellipsoid parameters.
                            if empty, use 3d shepp-logan

option
* `oversample::Integer`       oversampling factor (default:1)
* `checkfov::Bool`            warn if any ellipsoid is out of fov
* `how::Symbol`              `:fast` does it fast -- to do, only works slow
                                `:lowmem` uses less memory than :fast but a bit slower
                                `:slow` default
* `showmem::Bool`
* `hu_scale::Real`            use 1000 to scale shepp-logan to HU (default:1)
* `return_params::Bool`       if true, return both phantom and params

out
* `phantom`         `[nx ny nz]` image
* `params`          `[9 N]` ellipsoid parameters (only return if return_params=true)
"""
function ellipsoid_im(ig::MIRT_image_geom,
    params::AbstractArray{<:Real,2};
    oversample::Integer=1,
    checkfov::Bool=false,
    how::Symbol=:slow,
    showmem::Bool=false,
    hu_scale::Real=1,
    return_params::Bool=false)

    size(params,2) != 9 && throw("bad cuboid parameter vector size")
    params[:,9] .*= hu_scale
    args = (ig.nx, ig.ny, ig.nz, params, ig.dx, ig.dy, ig.dz,
            ig.offset_x, ig.offset_y, ig.offset_z, oversample, showmem)
    phantom = zeros(Float32, ig.nx, ig.ny, ig.nz)


    if checkfov
    	if !ellipsoid_im_check_fov(args...)
    		throw("ellipsoid exceeds FOV")
    	end
    end

    if how == :lowmem
        phantom += ellipsoid_im_lowmem(args...)
    elseif how == :fast
        phantom += ellipsoid_im_fast(args...)
    elseif how == :slow
        phantom += ellipsoid_im_slow(args...)
    else
        throw("bad how $how")
    end

    if return_params
        return (phantom, params)
    end
    return phantom
end


"""
`ellipsoid_im_slow()`

brute force fine grid - can use lots of memory
"""
function ellipsoid_im_slow(nx, ny, nz, params, dx, dy, dz,
    offset_x, offset_y, offset_z, over, showmem)

    phantom = zeros(Float32, nx*over, ny*over, nz*over)

    wx = (nx*over - 1)/2 + offset_x*over
    wy = (ny*over - 1)/2 + offset_y*over
    wz = (nz*over - 1)/2 + offset_z*over
    x = ((0:(nx * over - 1)) .- wx) * dx / over
    y = ((0:(ny * over - 1)) .- wy) * dy / over
    z = ((0:(nz * over - 1)) .- wz) * dz / over
    xmax = maximum(x)
    xmin = minimum(x)
    ymax = maximum(y)
    ymin = minimum(y)
    zmax = maximum(z)
    zmin = minimum(z)
    (xx, yy, zz) = ndgrid(x, y, z)

    #ticker reset
    np = size(params)[1]
    for ip in 1:np
        #ticker(mfilename, ip, np)

        par = params[ip, :]
        cx = par[1]
        cy = par[2]
        cz = par[3]
        rx = par[4]
        ry = par[5]
        rz = par[6]

        azim = par[7] * (pi/180)
        polar = par[8] * (pi/180)
        (xr, yr, zr) = rot3(xx .- cx, yy .- cy, zz .- cz, azim, polar)
        tmp = ((xr / rx).^2 + (yr / ry).^2 + (zr / rz).^2) .<=1
        value = Float32(par[9])
        phantom += value * tmp
    end
    return phantom
end


"""
`ellipsoid_im_fast()`

currently not working
only slow option works
"""
function ellipsoid_im_fast(nx, ny, nz, params, dx, dy, dz,
    offset_x, offset_y, offset_z, over, showmem)

    phantom = zeros(Float32, nx, ny, nz)

    wx = (nx-1)/2 + offset_x
    wy = (ny-1)/2 + offset_y
    wz = (nz-1)/2 + offset_z
    x = ((0:nx-1) .- wx) * dx
    y = ((0:ny-1) .- wy) * dy
    z = ((0:nz-1) .- wz) * dz
    xmax = maximum(x)
    xmin = minimum(x)
    ymax = maximum(y)
    ymin = minimum(y)
    zmax = maximum(z)
    zmin = minimum(z)
    (xx, yy, zz) = ndgrid(x, y, z)

    if over > 1
        tmp = ((1:over) - (over+1)/2) / over
        (xf, yf, zf) = ndgrid(tmp*dx, tmp*dy, tmp*dz)
        xf = xf[:]'
        yf = yf[:]'
        zf = zf[:]'
    end

    hx = abs(dx) / 2
    hy = abs(dy) / 2
    hz = abs(dz) / 2

    #ticker reset
    np = size(params)[1]
    for ip in 1:np
        #ticker(mfilename, ip, np)
        par = params[ip,:]
        cx = par[1]
        cy = par[2]
        cz = par[3]
        rx = par[4]
        ry = par[5]
        rz = par[6]

        azim = par[7] * (pi/180)
        polar = par[8] * (pi/180)

        xs = xx .- cx
        ys = yy .- cy
        zs = zz .- cz

        (xr, yr, zr) = rot3(xs, ys, zs, azim, polar)
        if over == 1
            vi = ((xr / rx).^2 + (yr / ry).^2 + (zr / rz).^2) .<= 1
            value = Float32(par[9])
            phantom += value * vi
        end

        #= check all 8 corners of the cube that bounds
        all possible 3D rotations of the voxel =#
        hh = sqrt(hx^2 + hy^2 + hz^2)
        vi = true # voxels entirely inside the ellipsoid
        #vo = true # voxels entirely outside the ellipsoid

        for ix in -1:1, iy in -1:1, iz in -1:1
            xo = xr .+ ix*hh
            yo = yr .+ iy*hh
            zo = zr .+ iz*hh
            vi = vi .& (((xo/rx).^2 + (yo/ry).^2 + (zo/rz).^2) .< 1)
        end

        vo = false #to do. for now, "outside" test is failing
        if ip == 1
            throw("todo:must debug this")
        end
        if any(vi[:] & vo[:])
            throw("bug")
        end
        #=
        if 0
        	% coordinates of "outer" corner of each voxel, relative to ellipsoid center
        	sign_p = @(x) (x >= 0) * sqrt(3); % modified sign()
        	xo = xr + sign_p(xr) * hx;
        	yo = yr + sign_p(yr) * hy;
        	zo = zr + sign_p(zr) * hz;

        	% voxels that are entirely inside the ellipsoid
        	vi = (xo / rx).^2 + (yo / ry).^2 + (zo / rz).^2 <= 1;
        end

        if 0
        	% coordinates of "inner" corner of each pixel, relative to ellipse center
        	sign_n = @(x) (x > 0) * sqrt(3); % modified sign()
        	xi = xr - sign_n(xs) * hx;
        	yi = yr - sign_n(ys) * hy;
        	zi = zr - sign_n(zs) * hz;

        	% voxels that are entirely outside the ellipsoid
        	vo = (max(abs(xi),0) / rx).^2 + (max(abs(yi),0) / ry).^2 ...
        		+ (max(abs(zi),0) / rz).^2 >= 1;
        end
        =#

        edge = !vi & !vo
        if showmem
            println("edge fraction ",
                sum(edge[:]) / prod(size(edge)), "=",
                sum(edge[:]), "/", prod(size(edge)))
        end

        x = xx[edge] .- cx
        y = yy[edge] .- cy
        z = zz[edge] .- cz
        x = x .+ xf'
    	y = y .+ yf'
    	z = z .+ zf'
        (xr, yr, zr) = rot3(x, y, z, azim, polar)
        in = ((xr/rx).^2 + (yr/ry).^2 + (zr/rz).^2) .<= 1
        tmp = mean(in, 2)
        gray = Float32(vi)
        gray[edge] = tmp
        #=
        if 0 % todo: help debug
            ee = (gray > 0) & (gray < 1);
            im(ee)
            im(vi)
	    prompt
		    %minmax(tmp)
		    %clf, im pl 1 2
		    %im(tmp)
	    end=#

        value = Float32(par[9])
        phantom += value*gray
    end
    return phantom
end

"""
`ellipsoid_im_lowmem()`

this version does 'one slice at a time' to reduce memory
"""
function ellipsoid_im_lowmem(nx, ny, nz, params, dx, dy, dz,
    offset_x, offset_y, offset_z, over, showmem)

    phantom = zeros(Float32, nx, ny, nz)
    for iz in 1:nz
        offset_z_new = (nz-1)/2 + offset_z - (iz-1)
        phantom[:,:,iz] = ellipsoid_im_fast(nx, ny, 1, params, dx, dy, dz,
                            offset_x, offset_y, offset_z_new, over, showmem && iz == 1)
    end
    return phantom
end


"""
`ellipsoid_im_check_fov()`
"""
function ellipsoid_im_check_fov(nx, ny, nz, params,
        dx, dy, dz, offset_x, offset_y, offset_z, over, showmem)
    wx = (nx - 1)/2 + offset_x
    wy = (ny - 1)/2 + offset_y
    wz = (nz - 1)/2 + offset_z
    xx = ((0:nx - 1) .- wx) * dx
    yy = ((0:ny - 1) .- wy) * dy
    zz = ((0:nz - 1) .- wz) * dz
    @show wz, zz
    xmax = maximum(xx)
    xmin = minimum(xx)
    ymax = maximum(yy)
    ymin = minimum(yy)
    zmax = maximum(zz)
    zmin = minimum(zz)

    ok = true

    for ip in 1:size(params)[1]
        par = params[ip, :]
        cx = par[1]
        cy = par[2]
        cz = par[3]
        rx = par[4]
        ry = par[5]
        rz = par[6]

        if (cx + rx > xmax) || (cx - rx < xmin)
            throw("fov: x range $xmin $xmax, cx=$cx, rx=$rx")
            ok = false
        end
        if (cy + ry > ymax) || (cy - ry < ymin)
            throw("fov: y range $ymin $ymax, cy=$cy, ry=$ry")
            ok = false
        end
        @show cz, rz, zmax, zmin
        if (cz + rz > zmax) || (cz - rz < zmin)
            throw("fov: z range $zmin $zmax, cz=$cz, rz=$rz")
		    ok = false
	    end
    end
    return ok
end


"""
`phantom = ellipsoid_im(nx, dx, params; args...)`

specifying voxel size of `dx` and ellipsoid `params`
"""
function ellipsoid_im(nx::Integer, dx::Real, params;args...)
    ig = image_geom(nx=nx, dx=1)
    return ellipsoid_im(ig, params; args...)
end

"""
`phantom = ellipsoid_im(nx::Integer, params; args...)`

voxel size of `dx=1` and ellipsoid `params`
"""
function ellipsoid_im(nx::Integer, params; args...)
    return ellipsoid_im(nx, 1., params; args...)
end

"""
`phantom = ellipsoid_im(nx::Integer, ny::Integer=nx, dx::Real=1, args...)`

image of size `nx` by `ny` (default `nx`) with specified `dx` (default 1)
defaults to `:zhu`
"""
function ellipsoid_im(nx::Integer, ny::Integer=nx, dx::Real=1, args...)
    if image_geom(nx=nx, ny=ny, dx=dx, args...)
        return ellipsoid_im(ig, :zhu; args...)
    end
end

"""
`phantom = ellipsoid_im(ig, ptype; args...)`

`ptype = :zhu | :kak | :e3d | :spheroid`
"""
function ellipsoid_im(ig::MIRT_image_geom, ptype::Symbol; args...)
    xfov = ig.fovs[1]
    yfov = ig.fovs[2]
    zfov = ig.fovs[3]

    if ptype == :zhu
        params = shepp_logan_3d_parameters(xfov, yfov, zfov, :zhu)
    elseif ptype == :kak
        params = shepp_logan_3d_parameters(xfov, yfov, zfov, :kak)
    elseif ptype == :e3d
        params = shepp_logan_3d_parameters(xfov, yfov, zfov, :e3d)
    elseif ptype == :spheroid
        params = spheroid_params(xfov, yfov, zfov, ig.dx, ig.dy, ig.dz)
    else
        throw("bad phantom symbol $ptype")
    end
    return ellipsoid_im(ig, params; args...)
end


"""
`phantom = ellipsoid_im(ig; args...)`

`:zhu` (default) for given image geometry `ig`
"""
function ellipsoid_im(ig::MIRT_image_geom; args...)
    return ellipsoid_im(ig, :zhu; args...)
end

"""
`rot3`
"""
function rot3(x, y, z, azim, polar)
    if polar != 0
        throw("z (polar) rotation not done")
    end
    xr = cos(azim) * x + sin(azim) * y
    yr = -sin(azim) * x + cos(azim) * y
    zr = z
    return (xr, yr, zr)
end


"""
`shepp_logan_3d_parameters()`

most of these values are unitless 'fractions of field of view'
"""
function shepp_logan_3d_parameters(xfov, yfov, zfov, ptype)
    # parameters from Kak and Slaney, typos ?
    ekak = Float32[
        0       0       0       0.69    0.92    0.9     0   0   2.0
        0       0       0       0.6624  0.874   0.88    0   0   -0.98
        -0.22   0       -0.25   0.41    0.16    0.21    0   0   -0.98
        0.22    0       -0.25   0.31    0.11    0.22    72  0  -0.02
        0       0.1     -0.25   0.046   0.046   0.046   0   0   0.02
        0       0.1     -0.25   0.046   0.046   0.046   0   0   0.02
        -0.8    -0.65   -0.25   0.046   0.023   0.02    0   0   0.01
        0.06    -0.065  -0.25   0.046   0.023   0.02    90  0  0.01
        0.06    -0.105  0.625   0.56    0.04    0.1     90  0  0.02
        0       0.1     -0.625  0.056   0.056   0.1     0   0   -0.02
    ]

    #parameters from leizhu@standford.edu, says kak&slaney are incorrect
    ezhu = Float32[
    0      0         0       0.69        0.92        0.9     0      0       2.0
	0      -0.0184   0       0.6624	     0.874       0.88	 0      0	    -0.98
	-0.22  0	     -0.25   0.41	     0.16	     0.21	 -72    0	    -0.02
	0.22   0	     -0.25	 0.31	     0.11	     0.22	 72     0	     -0.02
	0	   0.35	     -0.25	 0.21	     0.25	     0.35	 0      0	     0.01
	0	   0.1	     -0.25	 0.046	     0.046	     0.046	 0      0	     0.01
	-0.08  -0.605	 -0.25	 0.046	     0.023	     0.02	 0      0	     0.01
	0	   -0.1	     -0.25	 0.046	     0.046	     0.046	 0      0	     0.01
	0	   -0.605	 -0.25   0.023	     0.023     	 0.023	 0      0	     0.01
	0.06   -0.605	 -0.25	 0.046	     0.023	     0.02	 -90    0     	 0.01
	0.06   -0.105	 0.0625	 0.056	     0.04	     0.1	 -90    0      	 0.02
	0	   0.1	     0.625	 0.056	     0.056	     0.1	 0      0	     -0.02
    ]


    if ptype == :zhu
        params = ezhu
    elseif ptype == :kak
        params = ekak
    #elseif ptype == :shepp_logan_e3d || ptype == :e3d
        #params = e3d[:, [5:7 2:4 8 1]]
    else
        throw("unknown parameter type $ptype")
    end

    params[:,[1,4]] .*= xfov/2
    params[:,[2,5]] .*= yfov/2
    params[:,[3,6]] .*= zfov/2
    return params
end

"""
`spheroid_params()`
"""
function spheroid_params(xfov, yfov, zfov, dx, dy, dz)
    #xfov = nx * dx, number * size
    xradius = (xfov/2) - dx
    yradius = (yfov/2) - dy
    zradius = (zfov/2) - dz
    params =[
    0 0 0 xradius yradius zradius 0 0 1
    ]
    return params
end


"""
`ellipsoid_im()`

show docstrings
"""
function ellipsoid_im()
    @doc ellipsoid_im
end

"""
`ellipsoid_im_show()`
"""
function ellipsoid_im_show()
    ig = image_geom(nx=512, nz=64, dz=0.625, fov=500)
    ig = ig.down(8)

    x = ellipsoid_im(ig, :zhu; hu_scale=1000, how=:slow)
    p3 = jim(x, title="test") #clim=[900,1100]

    spheroid = ellipsoid_im(ig, :spheroid; how=:slow)
    p2 = jim(spheroid, title="spheroid")

    #x2 = ellipsoid_im(ig, :zhu; how=:lowmem)
    #p2 = jim(x2, title="zhu, lowmem")

    plot(p2, p3)
end

"""
`ellipsoid_im_test()`
"""
function ellipsoid_im_test()
    ig = image_geom(nx=512, nz=64*2, dz=0.625, fov=500)
    ig = ig.down(8)

    #test different ellipses
    e1 = ellipsoid_im(ig)
    e2 = ellipsoid_im(ig, :zhu)
    e3 = ellipsoid_im(ig, :kak)
    e4 = ellipsoid_im(ig; checkfov=true)
    e5 = ellipsoid_im(ig; showmem=true)
    e6 = ellipsoid_im(ig; return_params=true)

    #ell1 = ellipsoid_im(ig, :zhu; how=:fast) # fast doesn't work
    #ell2 = ellipsoid_im(ig, :zhu; how=:lowmem) # lowmem calls fast - doesn't work
end



"""
`ellipsoid_im(:test)`

`ellipsoid_im(:show)`

run tests
"""
function ellipsoid_im(test::Symbol)
	if test == :show
		return ellipsoid_im_show()
	end
	test != :test && throw(ArgumentError("test $test"))
	ellipsoid_im()
    ellipsoid_im(:show)
	ellipsoid_im_test()
	true
end

ellipsoid_im(:show)
ellipsoid_im(:test)
