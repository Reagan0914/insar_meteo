% Based on codes by David Bekaert and Andrew Hooper from packages TRAIN
% (https://github.com/dbekaert/TRAIN) and
% StaMPS (https://homepages.see.leeds.ac.uk/~earahoo/stamps/).

function out = staux(fun, varargin)
    
    switch(fun)
        case 'save_llh'
            save_llh();
        case 'save_binary'
            save_binary(varargin{:});
        case 'load_binary'
             out = load_binary(varargin{:});
        case 'boxplot_los'
             out = boxplot_los(varargin{:});
        case 'binned_statistic'
             out = binned_statistic(varargin{:});
        case 'binned_statistic_2d'
             out = binned_statistic_2d(varargin{:});
        case 'clap'
             out = clap(varargin{:});
        case 'iterate_unwrapping'
             out = iterate_unwrapping(varargin{:});
        case 'plot'
             out = plot(varargin{:});
        case 'plot_scatter'
             out = plot_scatter(varargin{:});
        case 'plot_loop'
             out = plot_loop(varargin{:});
        case 'plot_ph_grid'
             out = plot_ph_grid(varargin{:});
        case 'ps_output'
             out = plot_ph_grid();
        case 'rel_std_filt'
             out = rel_std_filt(varargin{:});
        case 'report'
            report();
        case 'crop'
            crop(varargin);
        case 'crop_reset'
            crop_reset();
        otherwise
            error(['Unknown function ', fun]);
    end
end

function varargout = boxplot_los(varargin)
doc = {
''
'function h = BOXPLOT_LOS(plot_flags, out, ...)'
''
'The plot will be saved to an image file defined by the _out_ argument. No '
'figure will pop up.'
'Plots the boxplot of LOS velocities defined by plot_flags.'
'Accepted plot flags are the same flags accepted by the ps_plot function,'
'with some extra rules.'
'    1) Multiple plot flags must be defined in a cell array, e.g.'
'    boxplot_los({''v-do'', ''v-da''});'
'    2) If we have the atmospheric correction option (''v-da''), the'
'    cooresponding atmospheric correction flag must be defined like this:'
'    ''v-da/a_e''. This denotes the DEM error and ERA-I corrected velocity'
'    values. Atmospheric coretcions can be calculated with TRAIN.'
'' 
'  Additional options to the boxplot function can be passed using varargin.'
'  - ''fun'' : function to be applied to the velocity values; default value:'
'            nan (no function is applied); function should return a vector'
'            (in the case of a single plot flag) or a matrix'
'            (in the case of multiple plot flags).'
'  - ''boxplot_opt'': varargin arguments for boxplot, given in a cell array;'
'                  e.g.: ''boxplot_opt'', {''widths'', 0.5, ''whisker'', 2.0}'
'                  See the help of the boxplot function for additinal '
'                  information. Default value: nan (no options)'
''
'  The function returns the function handle _h_ to the boxplot.'
''
};

    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end

    p = inputParser();
    
    p.FunctionName = 'boxplot_los';
    p.addRequired('plot_flags', @(x) ischar(x) | iscell(x));
    p.addRequired('out', @(x) ischar(x));
    
    p.addParameter('fun', @(x) x, @(x) isa(x, 'function_handle'));
    p.addParameter('boxplot_opt', nan, @iscell);
    
    p.parse(varargin{:});
    args = p.Results;
    
    % loading ps velocities
    vv = load_ps_vel(args.plot_flags);
    
    if isa(args.fun, 'function_handle')
        vv = args.fun(vv); % apply the function
    end

    % set up labels
    if iscell(args.boxplot_opt)
        n_var = length(args.boxplot_opt);
        
        % labels are the velocity flags
        args.boxplot_opt{n_var + 1} = 'labels';
        args.boxplot_opt{n_var + 2} = args.plot_flags;
        
        boxopt = args.boxplot_opt;
    else
        % labels are the velocity flags
        boxopt{1} = 'labels';
        boxopt{2} = args.plot_flags;
    end
    
    % by default it will not show the figure
    % instead it will save it to an image file
    h = figure('visible', 'off');
    boxplot(vv, boxopt{:});

    ylabel('LOS velocity [mm/yr]');
    saveas(h, args.out);
    varagout = h;
end

function [] = rel_std_filt(varargin)
doc = {
''
'function REL_STD_FILT(max_rel_std)'
''
'Filters calculated LOS velocities based in their relative standard deviations.'
'Relative standard deviation = (standard deviation / mean) * 100 (conversion into %).'
''
'- max_rel_std       (input) maximum allowed realtive standard deviation'
''
'Filtered LOS velocities will be saved into "ps_data_filt.xy", in ascii format.'
''
};

    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end
    
    % parse input arguments
    p = inputParser();
    p.FunctionName = 'rel_std_filt';
    p.addRequired('max_rel_std', @isscalar);

    p.parse(varargin{:});
    args = p.Results;
    
    % create ps_data.xy if it does not exist
    if ~exist('ps_data.xy', 'file')
        ps_output;
    end
    
    if ~exist('ps_mean_v_std.xy', 'file')
        ps_mean_v;
    end
    
    ps_std = load('ps_mean_v_std.xy', '-ascii');
    ps_data = load('ps_data.xy', '-ascii');
    
    rel_std = ps_data(:,3) ./ ps_std(:,3) * 100;
    
    idx = rel_std < args.max_rel_std;
    
    before = size(ps_data, 1);
    after = sum(idx);
    
    ps_data = ps_data(idx,:);
    
    fprintf(['Number of points before filtering: %d\n', ...
             'Number of points after filtering: %d\n'], before, after);
    
    save('ps_data_filt.xy', 'ps_data', '-ascii');
end

function [] = iterate_unwrapping(varargin)
doc = {
''
'function ITERATE_UNWRAPPING(numiter)'
''
'Simply iterate the unwrapping process _numiter_ times.'
'At every iteration the spatially-correlated look angle error is calculated '
'(StaMPS Step 7) can be calculated.'
''
'At the start of the iteration and at every iteration step the phase residuals '
'will be plotted into a png file, named iteration_(ii).png'
'where ii is the iteration step.'
''
'- numiter:       (input) number of iteraions'
'- ''scla'', false: (optional) by default SCLA corrections will NOT be calculated'
''
};

    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end

    p = inputParser();
    p.FunctionName = 'iterate_unwrapping';
    p.addRequired('numiter', @isscalar);
    p.addParameter('scla', false, @(x) isa(x, 'logical'));

    p.parse(varargin{:});
    args = p.Results;
    
    if args.scla
        end_step = 7;
    else
        end_step = 6;
    end
    
    % remove previous pngs
    delete iteration_*.png;

    h = figure; set(h, 'Visible', 'off');

    % plot starting residuals
    h = ps_plot('rsb');
    print('-dpng', '-r300', sprintf('iteration_%d.png', 0));
    close(h);
    
    for ii = 1:args.numiter
        fprintf('################\n');
        fprintf('ITERATION #%d\n', ii);
        fprintf('################\n');
        stamps(6,end_step);
        h = figure; set(h, 'Visible', 'off');
        h = ps_plot('rsb');
        print('-dpng', '-r300', sprintf('iteration_%d.png', ii));
        close(h);
    end
end

function [] = plot_loop(varargin)
doc = {
'function plot_loop(loop)'
''
'Plots residual phase terms (''rsb'') for the selected'
'interferograms.'
''
'- loop: (input) vector of interferogram indices'
''
'E.g.: plot_loop([1 2 3]); will plot ''rsb'' values for '
'IFG 1, 2 and 3.'
};

    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end

    p = inputParser();
    p.FunctionName = 'plot_loop';
    p.addRequired('loop', @isvector);

    p.parse(varargin{:});
    args = p.Results;

    ps_plot('rsb', 1, 0, 0, args.loop);
end

function varargout = binned_statistic(varargin)
doc = {
'binned = binned_statistic(x, y, ...)'
''
'Sorts y values into bins defined along x values.'
'By default sums y values in each of the x bins.'
''
'- x and y: (input) x and y value pairs, should be'
'a vector with the same number of elements'
''
'- ''bins'': (input, optional) number of bins or bin'
'edges defined by a vector (default: 10)'
''
'- ''fun'': (input, optional) function to apply to'
'y values in each bin. By default this is a summation'
''
'E.g. y_binned = binned_statistic(x, y, ''bins'', 100, ...'
'                                 ''fun'', @mean)'
'This will bin y values into x bins and calculate their'
'mean in each x bins. 100 bins will be placed evenly along'
'the values of x.'
};

    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end
    
    p = inputParser();
    
    p.addRequired('x', @isvector);
    p.addRequired('y', @isvector);
    
    % 10 bins by default
    p.addParameter('bins', 10, @(x) isvector(x) || isscalar(x));
    
    % default behaviour is summing y values in x bins
    p.addParameter('fun', nan, @(x) isnan(x) || ...
                                      isa(x, 'function_handle'));
    
    p.parse(varargin{:});
    args = p.Results;
    
    x = args.x;
    y = args.y;
    fun = args.fun;
    bins = args.bins;
    
    if isscalar(bins)
        bins = linspace(min(x), max(x), bins);
    end
    
    % calculate indices that place y values into
    % their respective x bins
    [~, idx] = histc(x, bins);
    
    % do not select values that are out of the range
    % of x bins
    y = y(idx > 0.0);
    idx = idx(idx > 0.0);
    
    if isnan(fun)
        binned = accumarray(idx', y', []);
    else
        binned = accumarray(idx', y', [], fun);
    end
    varargout{1} = binned;
    varargout{2} = bins;
end

function varargout = binned_statistic_2d(varargin)
doc = {
'binned = binned_statistic_2d(x, y, z, ...)'
''
'Sorts z values into bins defined along (x,y) values.'
'By default sums z values in each of the (x,y) bins.'
''
'- x, y and z: (input) x, y and z value triplets, should be'
'vectors with the same number of elements'
''
'- ''xbins'': (input, optional) number of bins or bin'
'edges defined by a vector along x (default: 10)'
''
'- ''ybins'': (input, optional) number of bins or bin'
'edges defined by a vector along y (default: 10)'
''
'- ''fun'': (input, optional) function to apply to'
'z values in each bin. By default this is a summation.'
''
'E.g. z_binned = binned_statistic(x, y, z, ''xbins'', 100, ...'
'                                 ''fun'', @mean)'
'This will bin z values into (x,y) bins and calculate their'
'mean in each (x,y) bins. 100 bins will be placed evenly along'
'the values of x and 10 bins along the values of y.'
};
 
    if nargin == 0
        fprintf('%s\n', doc{:});
        return;
    end
    
    p = inputParser();
    
    p.addRequired('x', @isvector);
    p.addRequired('y', @isvector);
    p.addRequired('z', @isvector);
    
    % 10 bins by default
    p.addParameter('xbins', 10, @(x) isvector(x) || isscalar(x));
    p.addParameter('ybins', 10, @(x) isvector(x) || isscalar(x));
    
    % default behaviour is summing z values in (x,y) bins
    p.addParameter('fun', 'sum', @(x) ischar(x) || ...
                                      isa(x, 'function_handle'));
    
    p.parse(varargin{:});

    x = p.Results.x;
    y = p.Results.y;
    z = p.Results.z;
    fun = p.Results.fun;
    xbins = p.Results.xbins;
    ybins = p.Results.ybins;

    if isscalar(xbins)
        xbins = linspace(min(x), max(x), xbins);
    end

    if isscalar(ybins)
        ybins = linspace(min(y), max(y), ybins);
    end


    % calculate indices that place (x,y) values into
    % their respective (x,y) bins
    [~, idx_x] = histc(x, xbins);
    [~, idx_y] = histc(y, ybins);

    % do not select values that are out of the range
    % of (x,y) bins
    idx = idx_x > 0.0 & idx_y > 0.0;
    
    z = z(idx);
    idx_x = idx_x(idx);
    idx_y = idx_y(idx);

    if strcmp(fun, 'sum')
        binned = accumarray([idx_x, idx_y], z, []);
    else
        binned = accumarray([idx_x, idx_y], z, [], fun);
    end
    varargout{1} = binned;
    varargout{2} = xbins;
    varargout{3} = ybins;
end

function varargout = clap(varargin)
% Modified CLAP filter. I used it to play around with the filter
% parameters. Feel free to ingore it.
    p = inputParser();
    
    p.addParameter('grid_size', 50, @isscalar)
    p.addParameter('alpha', 1, @isscalar)
    p.addParameter('beta', 0.3, @isscalar)
    p.addParameter('low_pass', 800, @isscalar)
    p.addParameter('win_size', 32, @isscalar)
    p.addParameter('ifg_list', [], @(x) isscalar(x))
    
    p.parse(varargin{:});
    
    grid_size = p.Results.grid_size;
    clap_alpha = p.Results.alpha;
    clap_beta = p.Results.beta;
    low_pass_wavelength = p.Results.low_pass;
    n_win = p.Results.win_size;
    ifg_idx = p.Results.ifg_list;
    
    freq0 = 1 / low_pass_wavelength;
    freq_i= -n_win / grid_size / n_win / 2:1 / grid_size / n_win:(n_win-2) / ...
             grid_size / n_win / 2;
    butter_i = 1 ./ (1 + (freq_i / freq0).^(2*5));
    low_pass = butter_i' * butter_i;
    low_pass = fftshift(low_pass);

    ps=load('ps1.mat');
    bp=load('bp1.mat');

    phin=load('ph1.mat');
    ph=phin.ph;
    clear phin

    if isempty(ifg_idx)
        n_ifg = ps.n_ifg;
        ifg_idx = 1:n_ifg;
    elseif isvector(ifg_idx)
        n_ifg = length(ifg_idx);
    else
        n_ifg = 1;
        ifg_idx = [ifg_idx];
    end
            
    bperp = ps.bperp(ifg_idx);
    n_image = ps.n_image;
    n_ps = ps.n_ps;
    ifgday_ix = ps.ifgday_ix(ifg_idx,:);
    xy = ps.xy;

    K_ps = zeros(n_ps,1);
    
    clear ps

    xbins = min(xy(:,2)):grid_size:max(xy(:,2));
    ybins = min(xy(:,3)):grid_size:max(xy(:,3));

    n_i = length(xbins);
    n_j = length(ybins);
    ph_grid = zeros(n_i, n_j, 'single');
    ph_filt = zeros(n_j, n_i, 'single');

    
    da = load('da1.mat');
    D_A = da.D_A;
    clear da

    weighting = 1 ./ D_A;

    ph_weight = ph(:,ifg_idx).*exp(-j * bp.bperp_mat(:,ifg_idx).* ...
                repmat(K_ps, 1, n_ifg)) .* repmat(weighting, 1, n_ifg);
    
    if n_ifg == 1
        ph_grid = binned_statistic_2d(xy(:,2), xy(:,3), ph_weight, ...
                          'xbins', xbins, 'ybins', ybins);
        ph_filt = clap_filt(transpose(ph_grid), clap_alpha, clap_beta, ...
                                   n_win * 0.75, n_win * 0.25, low_pass);
    else            
        for ii = ifg_idx
            ph_grid = binned_statistic_2d(xy(:,2), xy(:,3), ph_weight(:,ii), ...
                              'xbins', xbins, 'ybins', ybins);
            ph_filt = clap_filt(transpose(ph_grid), clap_alpha, clap_beta, ...
                                       n_win * 0.75, n_win * 0.25, low_pass);
        end
    end
    varargout{1} = ph_filt;
    varargout{2} = ph_grid;
end

% Auxilliary function for plotting the output of the modified CLAP filter
function [] = plot_ph_grid(ph)
    figure();
    colormap('jet');
    imagesc(angle(ph));
    colorbar();
end

% Helper function that loads LOS velocities defined by plot_flags.
function vv = load_ps_vel(plot_flags)

    % if we have multiple plot_flags
    if iscell(plot_flags)
        
        n_flags = length(plot_flags);

        ps = load('ps2.mat');
        
        % allocating space for velocity values
        vv = zeros(size(ps.lonlat, 1), n_flags);
        
        clear ps;
        
        for ii = 1:n_flags % going through flags
            
            % splitting for atmospheric flags
            plot_flag = strsplit(plot_flags{ii}, '/');
            
            % write velocities into a mat file and load it    
            
            % if we have atmospheric flag
            if length(plot_flag) > 1
                ps_plot(plot_flag{1}, plot_flag{2}, -1);
                v = load(sprintf('ps_plot_%s', lower(plot_flag{1})));
            else
                ps_plot(plot_flag{1}, -1);
                v = load(sprintf('ps_plot_%s', lower(plot_flag{1})));
            end
    
            % put velocity values into the corresponding column
            vv(:,ii) = v.ph_disp;
        end % end for
    else
        % splitting for atmospheric flags
        plot_flag = strsplit(plot_flags, '/');
        
        % write velocities into a mat file and load it
        if length(plot_flag) > 1 % if we have atmospheric flag
            ps_plot(plot_flag{1}, plot_flag{2}, -1);
            v = load(sprintf('ps_plot_%s', lower(plot_flag{1})));
        else
            ps_plot(plot_flag{1}, -1);
            v = load(sprintf('ps_plot_%s', lower(plot_flag{1})));
        end
        vv = v.ph_disp;
    end
end

% Wrapper function for ps_plot with argument handling that is more user friendly
function varargout = plot(varargin)
    p = inputParser();
    
    p.FunctionName = 'plot';
    
    p.addRequired('value_type', @ischar);
    p.addRequired('out', @ischar);
    
    p.addParameter('background', 1, @isscalar);    
    p.addParameter('phase_lims', 0, @(x) isvector(x) || isscalar(x));
    p.addParameter('ref_ifg', 0, @isscalar);
    p.addParameter('ifg_list', [], @isvector);
    p.addParameter('n_x', 0, @isscalar);
    p.addParameter('cbar_flag', 0, @(x) x == 1 || x == 2 || x == 0);
    p.addParameter('textsize', 0, @isscalar);
    p.addParameter('textcolor', [], @isvector);
    p.addParameter('lon_rg', [], @isvector);
    p.addParameter('lat_rg', [], @isvector);
    
    p.parse(varargin{:});
    
    args = p.Results;
    
    value_type = strsplit(args.value_type, '/');
    
    if length(value_type) == 1
        h = ps_plot(value_type{1}, args.background, args.phase_lims, args.ref_ifg, ...
                    args.ifg_list, args.n_x, args.cbar_flag, args.textsize, ...
                    args.textcolor, args.lon_rg, args.lat_rg);
    elseif length(value_type) == 2
        h = ps_plot(value_type{1}, value_type{2}, args.background, args.phase_lims, ...
                    args.ref_ifg, args.ifg_list, args.n_x, args.cbar_flag, ...
                    args.textsize, args.textcolor, args.lon_rg, args.lat_rg);
    else
        error('');
    end
    
    saveas(h, args.out)
    varargout = h;
end

% Just a bunch of plots
function [] = report()
    plot('w', 'wrapped.png');
    plot('u', 'unwrapped.png');
    plot('u-do', 'unwrapped_do.png');
    plot('usb', 'unwrapped_sb.png');
    plot('rsb', 'rsb.png');
    plot('usb-do', 'unwrapped_sb_do.png');
    
    plot('V', 'vel.png');
    plot('Vs', 'vel_std.png');
    plot('V-do', 'vel_do.png');
    plot('Vs-do', 'vel_std_do.png');
    
end

% MODIFIED ps_output. For some reason save('data.txt', 'data', '-ascii')
% did not work for us. I made some simple modifications to make it work
% with my save_ascii function (see the last function in this library).

function [] = ps_output()
    %PS_OUTPUT write various output files 
    %
    %   Andy Hooper, June 2006
    %
    %   =======================================================================
    %   09/2009 AH: Correct processing for small baselines output
    %   03/2010 AH: Add velocity standard deviation 
    %   09/2011 AH: Remove code that reduces extreme values
    %   02/2015 AH: Remove code that reduces the extreme values in u-dm
    %   =======================================================================
    
    fprintf('Writing output files...\n')
    
    small_baseline_flag = getparm('small_baseline_flag',1);
    ref_vel = getparm('ref_velocity',1);
    lambda = getparm('lambda',1);
    
    load psver
    psname=['ps', num2str(psver)];
    rcname=['rc', num2str(psver)];
    phuwname=['phuw', num2str(psver)];
    sclaname=['scla', num2str(psver)];
    hgtname=['hgt', num2str(psver)];
    scnname=['scn', num2str(psver)];
    mvname=['mv', num2str(psver)];
    meanvname=['mean_v'];
    
    ps=load(psname);
    phuw=load(phuwname);
    rc=load(rcname);
    
    if strcmpi(small_baseline_flag,'y')
        n_image=ps.n_image;
    else
        n_image=ps.n_ifg;
    end
    
    %ijname=['ps_ij.txt'];
    ij=ps.ij(:,2:3);
    % save(ijname,'ij','-ASCII');
    save_ascii('ps_ij.txt', '%d %d\n', ij)
    
    
    %llname=['ps_ll.txt'];
    lonlat=ps.lonlat;
    % save(llname,'lonlat','-ASCII');
    save_ascii('ps_ll.txt', '%f %f\n', lonlat);
    
    
    %datename=['date.txt'];
    date_out=str2num(datestr(ps.day, 'yyyymmdd'));
    % save(datename,'date_out','-ascii','-double');
    save_ascii('date.txt', '%f\n', date_out);
    
    master_ix = sum(ps.master_day>ps.day) + 1;
    
    ref_ps = ps_setref;
    ph_uw = phuw.ph_uw - repmat(mean(phuw.ph_uw(ref_ps,:)), ps.n_ps,1);
    ph_w = angle(rc.ph_rc.*repmat(conj(sum(rc.ph_rc(ref_ps,:))), ps.n_ps,1));
    ph_w(:,master_ix) = 0;
    
    
    fid = fopen('ph_w.flt', 'w');
    fwrite(fid, ph_w', 'float');
    fclose(fid);
    
    fid = fopen('ph_uw.flt', 'w');
    fwrite(fid,ph_uw', 'float');
    fclose(fid);
    
    scla = load(sclaname);
    if exist([hgtname, '.mat'],'file')
        hgt = load(hgtname);
    else
        hgt.hgt = zeros(ps.n_ps,1);
    end
    
    ph_uw = phuw.ph_uw - scla.ph_scla - repmat(scla.C_ps_uw,1,n_image);
    
    %%% this is only approximate
    K_ps_uw = scla.K_ps_uw-mean(scla.K_ps_uw);
    dem_error = double(K2q(K_ps_uw, ps.ij(:,3)));
    
    hgt_idx = hgt.hgt == 0;
    
    if sum(hgt_idx)
        dem_error = dem_error - mean(dem_error(hgt_idx));
    end
    
    %dem_error=dem_error-mean(dem_error(hgt.hgt==0));
    dem_sort = sort(dem_error);
    min_dem = dem_sort(ceil(length(dem_sort)*0.001));
    max_dem = dem_sort(floor(length(dem_sort)*0.999));
    dem_error_tt = dem_error;
    dem_error_tt(dem_error < min_dem) = min_dem; % for plotting purposes
    dem_error_tt(dem_error>max_dem) = max_dem; % for plotting purposes
    dem_error_tt = [ps.lonlat, dem_error_tt];
    
    % save('dem_error.xy','dem_error_tt','-ascii');
    save_ascii('dem_error.xy', '%f %f %f\n', dem_error_tt);
    
    %%%
    
    clear scla phuw
    ph_uw = ph_uw - repmat(mean(ph_uw(ref_ps,:)), ps.n_ps,1);
    
    meanv = load(meanvname);
    % m(1,:) is master APS + mean deviation from model
    mean_v = - meanv.m(2,:)' * 365.25 / 4 / pi * lambda * 1000 + ref_vel * 1000;
    
    %v_sort=sort(mean_v);
    %min_v=v_sort(ceil(length(v_sort)*0.001));
    %max_v=v_sort(floor(length(v_sort)*0.999));
    %mean_v(mean_v<min_v)=min_v;
    %mean_v(mean_v>max_v)=max_v;
    
    
    %mean_v_name = ['ps_mean_v.xy'];
    mean_v = [ps.lonlat,double(mean_v)];
    %save(mean_v_name,'mean_v','-ascii');
    save_ascii('ps_mean_v.xy', '%f %f %f\n', mean_v);
    
    
    if exist(['./',mvname,'.mat'], 'file');
        mv = load(mvname);
        mean_v_std = mv.mean_v_std;
        v_sort = sort(mean_v_std);
        min_v = v_sort(ceil(length(v_sort)*0.001));
        max_v = v_sort(floor(length(v_sort)*0.999));
        mean_v_std(mean_v_std < min_v) = min_v;
        mean_v_std(mean_v_std > max_v) = max_v;
        mean_v_name = ['ps_mean_v_std.xy'];
        mean_v = [ps.lonlat,double(mean_v_std)];
        %save(mean_v_name,'mean_v','-ascii');
        save_ascii(mean_v_name, '%f %f %f\n', mean_v);
    end
    
    
    %%Note mean_v is relative to a reference point
    %%and dem_error is relative to mean of zero height points (if there are any)
    fid=fopen('ps_data.xy','w');
    fprintf(fid,'%f %f %4.4f %4.4f %4.4f\n',[mean_v,double(hgt.hgt),dem_error]');
    fclose(fid)
    
    for i=1:n_image
        ph=ph_uw(:,i);

        ph=-ph*lambda*1000/4/pi;
        ph=[ps.lonlat,double(ph)];
        %save(['ps_u-dm.',num2str(i),'.xy'],'ph','-ascii');
        save_ascii(['ps_u-dm.',num2str(i),'.xy'], '%f %f %f\n', ph);
    end

end

% Replacement for save(path, 'data', '-ascii')
function [] = save_ascii(path, format, data)

    [FID, msg] = fopen(path, 'w');
    
    if FID == -1
        error(['Could not open file: ', path, '\nError message: ', msg]);
    end

    fprintf(FID, format, data');
    fclose(FID);
    
end

function varargout = plot_scatter(varargin)

    check_matrix = @(x) validateattributes(x, {'numeric'}, ...
                                {'nonempty', 'finite', 'ndims', 2});
    
    p = inputParser;
    p.FunctionName = 'plot_scatter';
    p.addRequired('data', check_matrix);
    p.addParameter('out', nan, @(x) ischar(x) || isnan(x));
    p.addParameter('cols', 5, @isscalar);
    p.addParameter('psize', 1.0, @isscalar);
    p.addParameter('lon_rg', [], @isvector);
    p.addParameter('lat_rg', [], @isvector);
    p.addParameter('clims', 'auto', @(x) isscalar(x) || isvector(x));

    p.parse(varargin{:});
    
    data = p.Results.data;
    out = p.Results.out;
    fcols = p.Results.cols;
    psize = p.Results.psize;
    lon_rg = p.Results.lon_rg;
    lat_rg = p.Results.lat_rg;
    clims = p.Results.clims;
    
    ncols = size(data, 2);
    
    ps = load('ps2.mat');
    ll = ps.lonlat;
    clear ps;
    
    if ncols == 1
        fcols = 1;
        frows = 1;
    else
        frows = ceil(sqrt(ncols) - 1);
        frows = max(1, frows);
        fcols = ceil(ncols / frows);
        
        %if fcols * frows < ncols
        %    frows = frows + 1;
        %end
    end
    
    if isnan(out)
        h = figure();
    else
        h = figure('visible', 'off');
    end
    
    for ii = 1:ncols
        subplot_tight(frows, fcols, ii);
        scatter(ll(:,1), ll(:,2), psize, data(:,ii));
        caxis(clims);
        colorbar();
    end
    
    if ~isnan(out)
        saveas(h, out);
    end
    varargout = h;
end

function [] = corr_phase(ifg, value)

    [x, y] = ginput;

    load('phuw_sb2.mat')
    load('ps2.mat')

    ph_ifg = ph_uw(:, ifg);
    lon = lonlat(:, 1);
    lat = lonlat(:, 2);

    in = inpolygon(lon, lat, x, y);

    ph_ifg(in) = ph_ifg(in) + value;

    ph_uw(:, ifg) = ph_ifg;

    save('phuw_sb2.mat', 'ph_uw', 'msd')
end

function [] = plot_sb_baselines(ix)
    %PLOT_SB_BASELINES plot the small baselines in small_baselines.list
    %Optional an input argument ix can be specified containing a vector of the
    %small baseline interferograms to keep which will be plotted in the baseline plot.
    %
    %   Andy Hooper, June 2007
    %
    %   ======================================================================
    %   09/2010 AH: Add option to plot in MERGED directory
    %   09/2010 AH: For SMALL_BASELINES/MERGED don't plot dropped ifgs 
    %   12/2012 DB: Added meaning of ix to the syntax of the code
    %   04/2013 DB: Command variable
    %   03/2014 DB: Suppress command line output
    %   ======================================================================
    
    
    if nargin <1
       ix=[];
    end
    
    
    currdir=pwd;
    dirs=strread(currdir,'%s','delimiter','/');
    if strcmp(dirs{end},'SMALL_BASELINES') 
        [a,b] = system(['\ls -d [1,2]* | sed ''' 's/_/ /''' ' > small_baselines.list']);
        load ../psver
        psname=['../ps',num2str(psver)];
        small_baseline_flag='y';
    elseif strcmp(dirs{end},'MERGED') 
        cd ../SMALL_BASELINES
        [a,b] = system(['\ls -d [1,2]* | sed ''' 's/_/ /''' ' > ../MERGED/small_baselines.list']);
        cd ../MERGED
        load ../psver
        psname=['../ps',num2str(psver)];
        small_baseline_flag='y';
    else
        load psver
        psname=['ps',num2str(psver)];
        small_baseline_flag='n';
    end
    
    sb=load('small_baselines.list');
    n_ifg=size(sb,1);
    if small_baseline_flag=='y' & isempty(ix) & exist('./parms.mat','file')
        drop_ifg_index=getparm('drop_ifg_index');
        if ~isempty(drop_ifg_index)
           ix=setdiff([1:n_ifg],drop_ifg_index);
        end
    end
    
    if ~isempty(ix)
        sb=sb(ix,:);
    else 
        ix=1:size(sb,1);
    end
    
    ps=load(psname);
    
    n_ifg=size(sb,1);
    [yyyymmdd,I,J]=unique(sb);
    ifg_ix=reshape(J,n_ifg,2);
    x=ifg_ix(:,1);
    y=ifg_ix(:,2);
    
    
    day=str2num(datestr(ps.day,'yyyymmdd'));
    [B,I]=intersect(day,yyyymmdd);
    
    x=I(x);
    y=I(y);
    
    figure

    for i=1:length(x)
        l=line([ps.day(x(i)),ps.day(y(i))],[ps.bperp(x(i)),ps.bperp(y(i))]);
        text((ps.day(x(i))+ps.day(y(i)))/2,(ps.bperp(x(i))+ps.bperp(y(i)))/2,num2str(ix(i)));
        set(l,'color',[0 1 0],'linewidth',2)
    end

    hold on
    p=plot(ps.day,ps.bperp,'ro');
    set(p,'markersize',12,'linewidth',2)
    hold off
    %datetick('x',12)
    %set(gca,'FontSize',10);
    xlabel('Felvetel idopontja')
    ylabel('Meroleges bazisvonal (m)')
    dateaxis
end

function [] = crop(varargin)

    p = inputParser();
    p.FunctionName = 'crop';
    p.addRequired('lon_min', @isscalar);
    p.addRequired('lon_max', @isscalar);
    p.addRequired('lat_min', @isscalar);
    p.addRequired('lat_max', @isscalar);

    p.parse(varargin{:});
    lon_min = p.Results.lon_min;
    lon_max = p.Results.lon_max;
    lat_min = p.Results.lat_min;
    lat_max = p.Results.lat_max;
    
    if ~exist('ps2_old.mat', 'file')
        copyfile ps2.mat ps2_old.mat
    end

    if ~exist('pm2_old.mat', 'file')
        copyfile pm2.mat pm2_old.mat
    end

    if ~exist('hgt2_old.mat', 'file')
        copyfile hgt2.mat hgt2_old.mat
    end

    if ~exist('bp2_old.mat', 'file')
        copyfile bp2.mat bp2_old.mat
    end

    if ~exist('rc2_old.mat', 'file')
        copyfile rc2.mat rc2_old.mat
    end
    
    ps = load('ps2_old.mat');
    pm = load('pm2_old.mat');
    bp = load('bp2_old.mat');
    rc = load('rc2_old.mat');
    hgt = load('hgt2_old.mat');
    
    lon = ps.lonlat(:,1);
    lat = ps.lonlat(:,2);
    
    before = size(lon, 1);
    
    idx = ~(lon > lon_min & lon < lon_max & lat > lat_min & lat < lat_max);
    
    after = sum(~idx);
    
    ps.xy(idx,:) = [];
    ps.lonlat(idx,:) = [];
    ps.ij(idx,:) = [];
    
    pm.coh_ps(idx,:) = [];

    hgt.hgt(idx,:) = [];
    
    rc.ph_rc(idx,:) = [];
    
    bp.bperp_mat(idx,:) = [];
    
    fprintf('Number of datapoints before cropping: %e and after cropping: %e', ...
             before, after);
    
    save('hgt2.mat', '-struct', 'hgt');
    save('bp2.mat', '-struct', 'bp');

    save('rc2.mat', '-struct', 'rc');
    save('pm2.mat', '-struct', 'pm');
    
    save('ps2.mat', '-struct', 'ps');
end

%function [] = station_crop(varargin)
%
%
%end

function [] = crop_reset()
    movefile ps2_old.mat ps2.mat
    movefile pm2_old.mat pm2.mat
    movefile hgt2_old.mat hgt2.mat
    movefile bp2_old.mat bp2.mat
    movefile rc2_old.mat rc2.mat
end

function [] = save_llh()
    
    ps = load('ps2.mat');
        
    llh = zeros(size(ps.lonlat, 1), 3);
    llh(:,1:2) = ps.lonlat;
    
    clear ps;
    
    hgt = load('hgt2.mat');
    llh(:,3) = hgt.hgt;
    
    clear hgt;
    
    fid = sfopen('llh.dat', 'w');
    fwrite(fid, transpose(llh), 'double');
    fclose(fid);
    
end

function [] = save_binary(varargin)
    p = inputParser;
    p.FunctionName = 'save_binary';
    
    check_data = @(x) validateattributes(x, {'numeric'}, ...
                            {'nonempty', 'finite', 'ndims', 2});
    
    p.addRequired('data', check_data);
    p.addRequired('path', @ischar);
    p.addParameter('dtype', 'double', @ischar);
    
    p.parse(varargin{:});
    
    data  = p.Results.data;
    path  = p.Results.path;
    dtype = p.Results.dtype;

    ps = load('ps2.mat');
    
    n_lonlat = size(ps.lonlat, 1);
    
    if size(data, 1) ~= n_lonlat
        error('data should have the same number of rows as lonlat');
    end
    
    ll = zeros(n_lonlat, 2 + size(data, 2));
    ll(:,1:2) = ps.lonlat;
    clear ps;
    
    ll(:,3:end) = data;
    
    fid = sfopen(path, 'w');
    fwrite(fid, transpose(ll), dtype);
    fclose(fid);
end

function loaded = load_binary(varargin)

    p = inputParser();
    p.FunctionName = 'load_binary';
    
    p.addRequired('path', @ischar);
    p.addRequired('ncols', @(x) isscalar(x) & x > 0.0 & isfinite(x));
    p.addParameter('dtype', 'double', @ischar);
    
    p.parse(varargin{:});
    args = p.Results;
    
    fid = sfopen(args.path, 'r');
    loaded = transpose(fread(fid, [args.ncols, Inf], args.dtype));
    fclose(fid);
end

function [] = aaa()
    n_ifg_plot = size(ph_disp, 2);
    
    xgap = 0.1;
    ygap = 0.2;
    [Y, X] = meshgrid([0.7:-1 * ygap:0.1], [0.1:xgap:0.8]);
    
    if ~isempty(lon_rg)
        ix = lonlat(:,1) >= lon_rg(1) & lonlat(:,1) <= lon_rg(2);
        lonlat = lonlat(ix,:);
    end
    
    if ~isempty(lat_rg)
        ix = lonlat(:,2) >= lat_rg(1) & lonlat(:,2) <= lat_rg(2);
        lonlat = lonlat(ix,:);
    end
    
    max_xy = llh2local([max(lonlat), 0]', [min(lonlat), 0]);
    
    fig_ar = 4/3; % aspect ratio of figure window
    useratio = 1; % max fraction of figure window to use
    n_i = max_xy(2) * 1000;
    n_j = max_xy(1) * 1000;
    ar = max_xy(1) / max_xy(2); % aspect ratio (x/y)
    
    if n_x==0
        % number of plots in y direction
        n_y = ceil(sqrt((n_ifg_plot) * ar / fig_ar)); 
        n_x = ceil((n_ifg_plot)  / n_y);
        
        % figure with fixed aspect ratio
        fixed_fig = 1;
    else
        n_y = ceil((n_ifg_plot) / n_x);
        fixed_fig = 0;
    end
    
    d_x = useratio / n_x;
    d_y = d_x / ar * fig_ar;
    
    % TS figure exceeds fig size
    if d_y > useratio / n_y & fixed_fig == 1
        d_y = useratio / n_y; 
        d_x = d_y * ar / fig_ar;
        h_y = 0.95 * d_y;
        h_x = h_y * ar / fig_ar;
    
        fig_size = 0;
    elseif d_y > useratio/ n_y & fixed_fig == 0 
        h_y = 0.95 * d_y;
        h_x = h_y * ar / fig_ar;
    
        y_scale = d_y * n_y;
        d_y = d_y / y_scale;   
        
        % check to indicate fig needs to be adapted
        fig_size = 1;
        h_y = 0.95 * d_y;
    else
        h_y = 0.95 * d_y;
        h_x = h_y * ar / fig_ar;
        fig_size = 0;
    end
    y = 1 - d_y:-d_y:0;
    x = 1 - useratio:d_x:1-d_x;

    [imY, imX] = meshgrid(y, x);
    if textsize == 0
        textsize = round(10 * 4 / n_x);
        if textsize > 16
            textsize = 16;
        elseif textsize < 8
            textsize = 8;
        end
    end
    
    % text length
    l_t = 1 / 9 * abs(textsize) / 10;
    
    % text height
    h_t = 1 / 50 * abs(textsize) / 10;
    x_t = round((h_x - l_t) / h_x / 2 * n_j);
    y_t = round(h_t * 1.2 / h_y * n_i);
end
