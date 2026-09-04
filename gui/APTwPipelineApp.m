classdef APTwPipelineApp < handle
% APTWPIPELINEAPP  Interactive GUI front-end for the APTw_Pipeline.
%
% Wraps prepare_one_subject / run_APTw_subject / evaluate_subject_own_maps
% (lib/pipeline/) - the exact same functions Prepare_APTw_Data.m,
% Run_APTw_Pipeline.m and Evaluate_APTw_Results.m use - so results computed
% from the GUI are identical to results computed from the scripts. This app
% intentionally does NOT do the scanner/Olea comparison Evaluate_APTw_
% Results.m does - see that script for QC against a reference map.
%
% Written as a plain handle class (not an App Designer .mlapp) so it is
% plain-text/diffable and compiles cleanly with MATLAB Compiler. Launch via
% APTwGUI.m at the project root, or APTwPipelineApp() directly once lib/ is
% on the path.

    properties (Access = private)
        ProjectRoot char
        BinFolder   char
        LastDataRoot char = ''
        SelfExePath char = '' % this process's own executable path - only used/needed when isdeployed

        % ---- state ----
        Subjects = struct('Path', {}, 'ID', {}, 'Status', {}, 'Error', {})
        IsRunning logical = false
        CancelRequested logical = false
        AdvancedExpanded logical = false

        % ---- background batch run (each subject runs as its own detached
        % "matlab -batch" process, polled by a timer, so the GUI stays fully
        % interactive - and cancellable - while processing runs) ----
        RunWorkDir char = ''
        BatchQueueIndices = []
        BatchQueuePos double = 0
        BatchNFailed double = 0
        BatchTimer = []
        CurrentSubjIdx double = 0
        CurrentRunFiles = struct('argsFile', '', 'log', '', 'pid', '', 'done', '')
        CurrentStartTic = uint64(0)
        LogFilePos double = 0
        LogPendingPartial char = '' % text read but not yet newline-terminated, held for the next poll
        StageNames = {'Prepare (DICOM/MOCO)', 'Brain segmentation', 'WASABI B0/B1 fit', 'Denoise + B1 correction', 'Export (NIfTI/DICOM)'}
        StageStates = {'pending', 'pending', 'pending', 'pending', 'pending'}

        CurrentViewerResults = []
        CurrentViewerSpectra = []
        CurrentViewerSpectraSubject char = ''

        % ---- top-level containers ----
        UIFigure
        OuterGrid
        StatusBanner
        GridMain

        % ---- left: subjects ----
        SubjectTable
        AddFolderButton
        RemoveButton
        ClearButton
        SubjectCountLabel
        RunSelectedButton
        RunAllButton
        CancelButton
        RunStatusLabel
        ChecklistLabel

        % ---- left: basic config ----
        ForceDicomCheckBox
        ForceMocoCheckBox
        ForceSegCheckBox
        ForceWasabiCheckBox
        MetricDropDown
        B1CorrectedCheckBox
        SmoothSigmaSpinner
        SaveOutputsCheckBox

        % ---- left: advanced config ----
        LeftGrid
        AdvancedToggleButton
        AdvancedPanel
        SingleB1IdField
        WasabiIdField
        MaskThresholdSpinner
        UseC6CheckBox
        NumPCASpinner
        RescaleSlopeField
        RescaleInterceptField
        WindowCenterSpinner
        WindowWidthSpinner

        % ---- right: tabs ----
        TabGroup
        LogTab
        LogTextArea
        ViewerTab

        % ---- viewer controls ----
        SubjectDropDown
        MapDropDown
        CompareCheckBox
        CompareMapDropDown
        ColormapDropDown
        ResetWindowButton
        OpenFolderButton
        DisplayGrid
        MainAxes
        CompareAxes
        SliceSlider
        SliceLabel
        WMinSpinner
        WMaxSpinner
        HistAxes
        StatsTextArea
        SpectrumAxes
    end

    methods (Access = public)
        function app = APTwPipelineApp()
            app.ProjectRoot = app.resolveProjectRoot();
            app.BinFolder   = app.resolveBinFolder();
            if ~isdeployed
                addpath(genpath(fullfile(app.ProjectRoot, 'lib')));
            end
            app.LastDataRoot = app.pickDefaultDataRoot();
            app.RunWorkDir = fullfile(tempdir, 'APTwGUI_runs');
            if isdeployed && ispc
                app.SelfExePath = app.resolveSelfExePath();
            end

            app.buildUI();
            app.checkDependencies();
            app.refreshSubjectTable();
            app.refreshViewerSubjectList();
            app.updateChecklistDisplay();
            app.UIFigure.Visible = 'on';
        end
    end

    % =====================================================================
    %  setup
    % =====================================================================
    methods (Access = private)
        function root = resolveProjectRoot(~)
            % Works both run from source and packaged with MATLAB Compiler
            % (isdeployed - files unpacked under ctfroot() keep their
            % relative layout as long as gui/, lib/, bin/ are all added to
            % the compiler project with their folder structure preserved).
            if isdeployed
                root = ctfroot();
            else
                root = fileparts(fileparts(mfilename('fullpath'))); % .../gui/.. -> project root
            end
        end

        function b = resolveBinFolder(app)
            % Where dcm2niix.exe lives. In deployed mode this is NOT
            % fullfile(ctfroot(),'bin') - MATLAB Compiler does not place -a
            % folders at a fixed, predictable path inside the CTF archive
            % (see find_bundled_resource.m for what was actually observed) -
            % so it has to be located the same way at runtime.
            if isdeployed
                b = find_bundled_resource(app.ProjectRoot, 'dcm2niix.exe');
            else
                b = fullfile(app.ProjectRoot, 'bin');
            end
        end

        function p = resolveSelfExePath(~)
            % The path to THIS running process's own .exe - used only in compiled
            % (isdeployed) mode, where launchSubjectProcess relaunches this same
            % exe with a "--worker" flag instead of invoking matlab.exe (which
            % won't exist on a machine with no MATLAB installed). ctfroot() is
            % not reliably "the exe's own folder" across MATLAB Compiler
            % versions/extraction modes, so this asks Windows directly instead.
            try
                NET.addAssembly('System');
                proc = System.Diagnostics.Process.GetCurrentProcess();
                p = char(proc.MainModule.FileName);
            catch
                p = ''; % background runs will fail loudly with a clear "not found" error rather than silently
            end
        end

        function d = pickDefaultDataRoot(~)
            candidate = 'F:\CEST\Patient Data';
            if isfolder(candidate)
                d = candidate;
            else
                d = pwd;
            end
        end

        function checkDependencies(app)
            msgs = {};
            if isempty(which('spm'))
                msgs{end+1} = 'SPM12 not found on the MATLAB path (motion correction + brain segmentation need it)';
            end
            if ispc && ~isfile(fullfile(app.BinFolder, 'dcm2niix.exe')) && isempty(which('dcm2niix.exe'))
                msgs{end+1} = 'dcm2niix.exe not found (DICOM->NIfTI conversion needs it)';
            end
            if isempty(msgs)
                app.OuterGrid.RowHeight{1} = 0;
                app.StatusBanner.Visible = 'off';
            else
                app.StatusBanner.Text = ['MISSING DEPENDENCY: ' strjoin(msgs, '   |   ') '  -  add it to the MATLAB path and restart.'];
                app.StatusBanner.Visible = 'on';
                app.OuterGrid.RowHeight{1} = 30;
            end
        end
    end

    % =====================================================================
    %  UI construction
    % =====================================================================
    methods (Access = private)
        function buildUI(app)
            app.UIFigure = uifigure('Name', 'APTw Pipeline', 'Position', [80 50 1500 960], 'Visible', 'off');
            app.UIFigure.CloseRequestFcn = @(~,~) app.onCloseRequest();
            app.UIFigure.WindowScrollWheelFcn = @(~, evt) app.onScrollWheel(evt);

            app.OuterGrid = uigridlayout(app.UIFigure, [2 1]);
            app.OuterGrid.RowHeight = {0, '1x'};
            app.OuterGrid.Padding = [0 0 0 0];
            app.OuterGrid.RowSpacing = 0;

            app.StatusBanner = uilabel(app.OuterGrid, 'Text', '', 'FontColor', [0.55 0.1 0.1], ...
                'BackgroundColor', [1 0.85 0.7], 'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'Visible', 'off');
            app.StatusBanner.Layout.Row = 1; app.StatusBanner.Layout.Column = 1;

            app.GridMain = uigridlayout(app.OuterGrid, [1 2]);
            app.GridMain.Layout.Row = 2; app.GridMain.Layout.Column = 1;
            app.GridMain.ColumnWidth = {380, '1x'};

            app.buildLeftPanel(app.GridMain);
            app.buildRightPanel(app.GridMain);
        end

        function buildLeftPanel(app, parent)
            leftPanel = uipanel(parent, 'Title', '');
            leftPanel.Layout.Column = 1; leftPanel.Layout.Row = 1;

            app.LeftGrid = uigridlayout(leftPanel, [7 1]);
            app.LeftGrid.RowHeight = {22, '1x', 36, 150, 300, 26, 0};
            app.LeftGrid.Padding = [8 8 8 8]; app.LeftGrid.RowSpacing = 6;

            uilabel(app.LeftGrid, 'Text', 'Subjects', 'FontWeight', 'bold');

            app.SubjectTable = uitable(app.LeftGrid);
            app.SubjectTable.ColumnName = {'Subject', 'Status'};
            app.SubjectTable.ColumnWidth = {160, 160};
            app.SubjectTable.SelectionType = 'row';
            app.SubjectTable.Multiselect = 'on';
            app.SubjectTable.Layout.Row = 2;

            subjBtnGrid = uigridlayout(app.LeftGrid, [1 4]);
            subjBtnGrid.Layout.Row = 3; subjBtnGrid.Padding = [0 0 0 0]; subjBtnGrid.ColumnSpacing = 4;
            app.AddFolderButton = uibutton(subjBtnGrid, 'Text', 'Add Folder(s)', 'ButtonPushedFcn', @(~,~) app.onAddFolder());
            app.RemoveButton    = uibutton(subjBtnGrid, 'Text', 'Remove', 'ButtonPushedFcn', @(~,~) app.onRemove());
            app.ClearButton     = uibutton(subjBtnGrid, 'Text', 'Clear', 'ButtonPushedFcn', @(~,~) app.onClear());
            app.SubjectCountLabel = uilabel(subjBtnGrid, 'Text', '0 subject(s)', 'HorizontalAlignment', 'right');

            runGrid = uigridlayout(app.LeftGrid, [3 3]);
            runGrid.Layout.Row = 4; runGrid.Padding = [0 0 0 0]; runGrid.RowSpacing = 2; runGrid.ColumnSpacing = 4;
            runGrid.RowHeight = {24, 18, '1x'};
            app.RunSelectedButton = uibutton(runGrid, 'Text', 'Run Selected', 'ButtonPushedFcn', @(~,~) app.onRunSelected());
            app.RunAllButton      = uibutton(runGrid, 'Text', 'Run All', 'ButtonPushedFcn', @(~,~) app.onRunAll());
            app.CancelButton      = uibutton(runGrid, 'Text', 'Cancel', 'Enable', 'off', 'ButtonPushedFcn', @(~,~) app.onCancel(), ...
                'Tooltip', 'Immediately stops the subject currently processing (background process is killed). Remaining queued subjects are not started.');
            app.RunStatusLabel = uilabel(runGrid, 'Text', 'Idle.', 'FontColor', [0.3 0.3 0.3]);
            app.RunStatusLabel.Layout.Row = 2; app.RunStatusLabel.Layout.Column = [1 3];
            app.ChecklistLabel = uilabel(runGrid, 'Text', {''}, 'FontName', 'Consolas', 'FontSize', 12, ...
                'VerticalAlignment', 'top', 'FontColor', [0.25 0.25 0.25]);
            app.ChecklistLabel.Layout.Row = 3; app.ChecklistLabel.Layout.Column = [1 3];

            app.buildBasicConfigPanel(app.LeftGrid);

            app.AdvancedToggleButton = uibutton(app.LeftGrid, 'Text', char(9656) + " Advanced settings", ...
                'ButtonPushedFcn', @(~,~) app.onToggleAdvanced());
            app.AdvancedToggleButton.Layout.Row = 6;

            app.buildAdvancedConfigPanel(app.LeftGrid);
        end

        function buildBasicConfigPanel(app, parent)
            p = uipanel(parent, 'Title', 'Processing options');
            p.Layout.Row = 5;
            g = uigridlayout(p, [9 2]);
            g.RowHeight = repmat({24}, 1, 9);
            g.ColumnWidth = {'1x', 110};
            g.Padding = [6 4 6 4]; g.RowSpacing = 3;

            hdr = uilabel(g, 'Text', 'Force redo (default: reuse cached results):', 'FontWeight', 'bold');
            hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];

            app.ForceDicomCheckBox = uicheckbox(g, 'Text', 'DICOM -> NIfTI conversion');
            app.ForceDicomCheckBox.Layout.Row = 2; app.ForceDicomCheckBox.Layout.Column = [1 2];
            app.ForceMocoCheckBox = uicheckbox(g, 'Text', 'Motion correction');
            app.ForceMocoCheckBox.Layout.Row = 3; app.ForceMocoCheckBox.Layout.Column = [1 2];
            app.ForceSegCheckBox = uicheckbox(g, 'Text', 'Brain segmentation (SPM)');
            app.ForceSegCheckBox.Layout.Row = 4; app.ForceSegCheckBox.Layout.Column = [1 2];
            app.ForceWasabiCheckBox = uicheckbox(g, 'Text', 'WASABI B0/B1 fit');
            app.ForceWasabiCheckBox.Layout.Row = 5; app.ForceWasabiCheckBox.Layout.Column = [1 2];

            lbl = uilabel(g, 'Text', 'APTw metric:'); lbl.Layout.Row = 6;
            app.MetricDropDown = uidropdown(g, 'Items', {'MTRRex (rex) - recommended', 'Conventional (fs)'});
            app.MetricDropDown.Layout.Row = 6; app.MetricDropDown.Layout.Column = 2;

            app.B1CorrectedCheckBox = uicheckbox(g, 'Text', 'B1-corrected map', 'Value', true);
            app.B1CorrectedCheckBox.Layout.Row = 7; app.B1CorrectedCheckBox.Layout.Column = [1 2];

            lbl = uilabel(g, 'Text', 'Spatial smoothing sigma:'); lbl.Layout.Row = 8;
            app.SmoothSigmaSpinner = uispinner(g, 'Limits', [0 3], 'Step', 0.1, 'Value', 0);
            app.SmoothSigmaSpinner.Layout.Row = 8; app.SmoothSigmaSpinner.Layout.Column = 2;

            app.SaveOutputsCheckBox = uicheckbox(g, 'Text', 'Export NIfTI + DICOM after run', 'Value', true);
            app.SaveOutputsCheckBox.Layout.Row = 9; app.SaveOutputsCheckBox.Layout.Column = [1 2];
        end

        function buildAdvancedConfigPanel(app, parent)
            app.AdvancedPanel = uipanel(parent, 'Title', 'Advanced settings', 'Visible', 'off');
            app.AdvancedPanel.Layout.Row = 7;
            g = uigridlayout(app.AdvancedPanel, [11 2]);
            g.RowHeight = repmat({24}, 1, 11);
            g.ColumnWidth = {'1x', 130};
            g.Padding = [6 4 6 4]; g.RowSpacing = 3;

            lbl = uilabel(g, 'Text', 'APTw series ID:'); lbl.Layout.Row = 1;
            app.SingleB1IdField = uieditfield(g, 'text', 'Value', 'APTw_001');
            app.SingleB1IdField.Layout.Row = 1; app.SingleB1IdField.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'WASABI series ID:'); lbl.Layout.Row = 2;
            app.WasabiIdField = uieditfield(g, 'text', 'Value', 'WASAB');
            app.WasabiIdField.Layout.Row = 2; app.WasabiIdField.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'Brain mask threshold:'); lbl.Layout.Row = 3;
            app.MaskThresholdSpinner = uispinner(g, 'Limits', [0 1], 'Step', 0.05, 'Value', 0.2);
            app.MaskThresholdSpinner.Layout.Row = 3; app.MaskThresholdSpinner.Layout.Column = 2;

            app.UseC6CheckBox = uicheckbox(g, 'Text', 'Wide mask (everything but background air)', 'Value', true);
            app.UseC6CheckBox.Layout.Row = 4; app.UseC6CheckBox.Layout.Column = [1 2];

            lbl = uilabel(g, 'Text', 'PCA components kept:'); lbl.Layout.Row = 5;
            app.NumPCASpinner = uispinner(g, 'Limits', [1 30], 'Step', 1, 'Value', 15, 'RoundFractionalValues', 'on');
            app.NumPCASpinner.Layout.Row = 5; app.NumPCASpinner.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'DICOM rescale slope:'); lbl.Layout.Row = 6;
            app.RescaleSlopeField = uieditfield(g, 'numeric', 'Value', 0.000740738993, 'Limits', [-Inf Inf]);
            app.RescaleSlopeField.Layout.Row = 6; app.RescaleSlopeField.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'DICOM rescale intercept:'); lbl.Layout.Row = 7;
            app.RescaleInterceptField = uieditfield(g, 'numeric', 'Value', -24.1181, 'Limits', [-Inf Inf]);
            app.RescaleInterceptField.Layout.Row = 7; app.RescaleInterceptField.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'DICOM window center:'); lbl.Layout.Row = 8;
            app.WindowCenterSpinner = uispinner(g, 'Limits', [-Inf Inf], 'Step', 1, 'Value', 2);
            app.WindowCenterSpinner.Layout.Row = 8; app.WindowCenterSpinner.Layout.Column = 2;

            lbl = uilabel(g, 'Text', 'DICOM window width:'); lbl.Layout.Row = 9;
            app.WindowWidthSpinner = uispinner(g, 'Limits', [0.1 Inf], 'Step', 1, 'Value', 6);
            app.WindowWidthSpinner.Layout.Row = 9; app.WindowWidthSpinner.Layout.Column = 2;

            hint = uilabel(g, 'Text', 'DICOM encoding defaults match Olea''s own export - only change if you know why.', ...
                'FontColor', [0.4 0.4 0.4], 'WordWrap', 'on');
            hint.Layout.Row = [10 11]; hint.Layout.Column = [1 2];
        end

        function buildRightPanel(app, parent)
            app.TabGroup = uitabgroup(parent);
            app.TabGroup.Layout.Column = 2; app.TabGroup.Layout.Row = 1;

            app.LogTab = uitab(app.TabGroup, 'Title', 'Run & Log');
            logGrid = uigridlayout(app.LogTab, [2 1]);
            logGrid.RowHeight = {'1x', 28};
            app.LogTextArea = uitextarea(logGrid, 'Editable', 'off', 'FontName', 'Consolas', 'Value', {'Ready.'});
            clearLogBtn = uibutton(logGrid, 'Text', 'Clear Log', 'ButtonPushedFcn', @(~,~) app.onClearLog());
            clearLogBtn.Layout.Row = 2;

            app.ViewerTab = uitab(app.TabGroup, 'Title', 'Results Viewer');
            app.buildViewerTab(app.ViewerTab);
        end

        function buildViewerTab(app, parent)
            vg = uigridlayout(parent, [5 1]);
            vg.RowHeight = {32, '2x', 30, 34, '1x'};
            vg.Padding = [8 8 8 8]; vg.RowSpacing = 6;

            % ---- row 1: subject/map/colormap controls ----
            ctrl = uigridlayout(vg, [1 8]);
            ctrl.ColumnWidth = {130, '1x', 120, '1x', 110, 90, 110, 110};
            ctrl.Padding = [0 0 0 0];
            uilabel(ctrl, 'Text', 'Subject:');
            app.SubjectDropDown = uidropdown(ctrl, 'Items', {'(none)'}, 'ValueChangedFcn', @(~,~) app.onSubjectChanged());
            uilabel(ctrl, 'Text', 'Map:');
            app.MapDropDown = uidropdown(ctrl, 'Items', {'APTw'}, 'ValueChangedFcn', @(~,~) app.updateMainDisplay());
            app.CompareCheckBox = uicheckbox(ctrl, 'Text', 'Compare', 'ValueChangedFcn', @(~,~) app.onCompareToggled());
            app.CompareMapDropDown = uidropdown(ctrl, 'Items', {'APTw_rex'}, 'Enable', 'off', 'ValueChangedFcn', @(~,~) app.updateMainDisplay());
            app.ColormapDropDown = uidropdown(ctrl, 'Items', {'Parula', 'Diverging (blue-white-red)', 'Gray'}, ...
                'ValueChangedFcn', @(~,~) app.updateMainDisplay());
            app.ResetWindowButton = uibutton(ctrl, 'Text', 'Reset window', 'ButtonPushedFcn', @(~,~) app.onResetWindow());

            % ---- row 2: image display (main + compare) ----
            app.DisplayGrid = uigridlayout(vg, [1 2]);
            app.DisplayGrid.ColumnWidth = {'1x', 0};
            app.DisplayGrid.Padding = [0 0 0 0]; app.DisplayGrid.ColumnSpacing = 4;
            app.MainAxes = uiaxes(app.DisplayGrid);
            app.CompareAxes = uiaxes(app.DisplayGrid);
            app.CompareAxes.Visible = 'off';

            % ---- row 3: slice slider ----
            sliceGrid = uigridlayout(vg, [1 2]);
            sliceGrid.ColumnWidth = {'1x', 120};
            sliceGrid.Padding = [0 0 0 0];
            app.SliceSlider = uislider(sliceGrid, 'Limits', [1 2], 'Value', 1, ...
                'ValueChangedFcn', @(~,~) app.onSliceSliderChanged());
            app.SliceLabel = uilabel(sliceGrid, 'Text', 'Slice - / -', 'HorizontalAlignment', 'right');

            % ---- row 4: window/level + open-folder ----
            wlGrid = uigridlayout(vg, [1 6]);
            wlGrid.ColumnWidth = {70, 90, 30, 90, '1x', 130};
            wlGrid.Padding = [0 0 0 0];
            uilabel(wlGrid, 'Text', 'Window:');
            app.WMinSpinner = uispinner(wlGrid, 'Limits', [-Inf Inf], 'Step', 0.5, 'ValueChangedFcn', @(~,~) app.updateMainDisplay());
            uilabel(wlGrid, 'Text', 'to', 'HorizontalAlignment', 'center');
            app.WMaxSpinner = uispinner(wlGrid, 'Limits', [-Inf Inf], 'Step', 0.5, 'ValueChangedFcn', @(~,~) app.updateMainDisplay());
            uilabel(wlGrid, 'Text', '');
            app.OpenFolderButton = uibutton(wlGrid, 'Text', 'Open Zeval folder', 'ButtonPushedFcn', @(~,~) app.onOpenFolder());

            % ---- row 5: histogram/stats + spectrum inspector ----
            bottom = uigridlayout(vg, [1 2]);
            bottom.Padding = [0 0 0 0]; bottom.ColumnSpacing = 8;

            histPanel = uipanel(bottom, 'Title', 'Distribution (masked voxels)');
            histGrid = uigridlayout(histPanel, [2 1]);
            histGrid.RowHeight = {'2x', '1x'};
            app.HistAxes = uiaxes(histGrid);
            app.StatsTextArea = uitextarea(histGrid, 'Editable', 'off');

            specPanel = uipanel(bottom, 'Title', 'Click a voxel on the map to inspect its Z-spectrum');
            specGrid = uigridlayout(specPanel, [1 1]);
            app.SpectrumAxes = uiaxes(specGrid);
        end
    end

    % =====================================================================
    %  subject list management
    % =====================================================================
    methods (Access = private)
        function onAddFolder(app)
            folder = uigetdir(app.LastDataRoot, 'Select a subject folder, or a folder containing one sub-folder per subject');
            if isequal(folder, 0), return; end
            app.LastDataRoot = folder;
            cfg = app.buildCfg();
            if looks_like_subject_folder(folder, cfg)
                newPaths = {folder};
            else
                d = dir(folder);
                d = d([d.isdir] & ~ismember({d.name}, {'.', '..'}));
                candidates = fullfile(folder, {d.name});
                candidates = candidates(cellfun(@isfolder, candidates));
                isSubj = cellfun(@(f) looks_like_subject_folder(f, cfg), candidates);
                newPaths = candidates(isSubj);
                if any(~isSubj)
                    app.appendLog(sprintf('Skipped %d folder(s) under %s that do not look like subject folders.', nnz(~isSubj), folder));
                end
            end
            if isempty(newPaths)
                uialert(app.UIFigure, 'No subject folders found there (need a nii/ with the APTw/WASABI series, or raw DICOM series sub-folders).', 'Nothing added');
                return
            end
            added = 0;
            for i = 1:numel(newPaths)
                if ~any(strcmpi(newPaths{i}, {app.Subjects.Path}))
                    [~, id] = fileparts(newPaths{i});
                    app.Subjects(end+1) = struct('Path', newPaths{i}, 'ID', id, 'Status', app.detectStatus(newPaths{i}), 'Error', ''); %#ok<AGROW>
                    added = added + 1;
                end
            end
            app.appendLog(sprintf('Added %d subject(s) (%d already in the list were skipped).', added, numel(newPaths) - added));
            app.refreshSubjectTable();
            app.refreshViewerSubjectList();
        end

        function s = detectStatus(~, path)
            [~, id] = fileparts(path);
            resultsFile = fullfile(path, 'Zeval', [id '_APTw_results.mat']);
            regFiles = dir(fullfile(path, 'nii', '*_REG_*.nii'));
            if isfile(resultsFile)
                s = 'Processed (cached)';
            elseif ~isempty(regFiles)
                s = 'Prepared (cached)';
            else
                s = 'Queued';
            end
        end

        function onRemove(app)
            sel = app.SubjectTable.Selection;
            if isempty(sel), return; end
            rows = unique(sel(:));
            app.Subjects(rows) = [];
            app.refreshSubjectTable();
            app.refreshViewerSubjectList();
        end

        function onClear(app)
            app.Subjects = struct('Path', {}, 'ID', {}, 'Status', {}, 'Error', {});
            app.refreshSubjectTable();
            app.refreshViewerSubjectList();
        end

        function refreshSubjectTable(app)
            n = numel(app.Subjects);
            data = cell(n, 2);
            for i = 1:n
                data{i, 1} = app.Subjects(i).ID;
                data{i, 2} = app.Subjects(i).Status;
            end
            app.SubjectTable.Data = data;
            app.SubjectCountLabel.Text = sprintf('%d subject(s)', n);
        end
    end

    % =====================================================================
    %  config
    % =====================================================================
    methods (Access = private)
        function cfg = buildCfg(app)
            cfg = aptw_default_cfg();
            cfg.force_dicom_conversion = app.ForceDicomCheckBox.Value;
            cfg.force_moco             = app.ForceMocoCheckBox.Value;
            cfg.force_segmentation     = app.ForceSegCheckBox.Value;
            cfg.force_wasabi           = app.ForceWasabiCheckBox.Value;
            if startsWith(app.MetricDropDown.Value, 'MTRRex')
                cfg.aptw_metric = 'rex';
            else
                cfg.aptw_metric = 'fs';
            end
            cfg.aptw_b1_corrected      = app.B1CorrectedCheckBox.Value;
            cfg.spatial_smooth_sigma   = app.SmoothSigmaSpinner.Value;
            cfg.saveOutputs            = app.SaveOutputsCheckBox.Value;
            cfg.singleB1_id            = app.SingleB1IdField.Value;
            cfg.wasabi_id              = app.WasabiIdField.Value;
            cfg.wasabi_raw_id          = app.WasabiIdField.Value;
            cfg.mask_threshold         = app.MaskThresholdSpinner.Value;
            cfg.use_c6                 = app.UseC6CheckBox.Value;
            cfg.pca_components         = 1:round(app.NumPCASpinner.Value);
            cfg.dicom_rescale_slope    = app.RescaleSlopeField.Value;
            cfg.dicom_rescale_intercept = app.RescaleInterceptField.Value;
            cfg.dicom_window_center    = app.WindowCenterSpinner.Value;
            cfg.dicom_window_width     = app.WindowWidthSpinner.Value;
            cfg.emit_stage_markers     = true; % lets the checklist track progress - see run_APTw_subject.m
        end

        function onToggleAdvanced(app)
            app.AdvancedExpanded = ~app.AdvancedExpanded;
            if app.AdvancedExpanded
                app.AdvancedPanel.Visible = 'on';
                app.LeftGrid.RowHeight{7} = 320;
                app.AdvancedToggleButton.Text = char(9662) + " Advanced settings";
            else
                app.AdvancedPanel.Visible = 'off';
                app.LeftGrid.RowHeight{7} = 0;
                app.AdvancedToggleButton.Text = char(9656) + " Advanced settings";
            end
        end
    end

    % =====================================================================
    %  running the pipeline
    %
    %  Each subject runs as its OWN detached "matlab -batch" process (a
    %  runner .m script + a saved cfg .mat, launched via "start /B" so the
    %  system() call returns immediately) instead of running in-process.
    %  A timer polls that process's log/PID/done files every ~0.75s. This
    %  keeps the GUI fully responsive and interactive (progress updates,
    %  tab switching, viewing already-finished subjects) and Cancel now
    %  kills the running process immediately (taskkill) instead of only
    %  taking effect "after the current subject" - both of which a
    %  single blocking in-process call could never give us, since MATLAB's
    %  event loop cannot service the GUI while it is itself busy computing.
    % =====================================================================
    methods (Access = private)
        function onRunAll(app)
            app.runBatch(1:numel(app.Subjects));
        end

        function onRunSelected(app)
            sel = app.SubjectTable.Selection;
            if isempty(sel)
                uialert(app.UIFigure, 'Select one or more rows in the subject table first (click, or Ctrl/Shift+click for several).', 'No subjects selected');
                return
            end
            app.runBatch(unique(sel(:))');
        end

        function onCancel(app)
            if ~app.IsRunning, return; end
            app.CancelRequested = true;
            app.RunStatusLabel.Text = 'Cancelling...';
        end

        function runBatch(app, indices)
            if isempty(indices), return; end
            if app.IsRunning
                uialert(app.UIFigure, 'A run is already in progress.', 'Busy');
                return
            end
            if ~ispc
                uialert(app.UIFigure, 'Background batch processing (Run Selected/Run All) is currently only implemented on Windows.', 'Not supported');
                return
            end
            app.IsRunning = true;
            app.CancelRequested = false;
            app.BatchQueueIndices = indices;
            app.BatchQueuePos = 0;
            app.BatchNFailed = 0;
            app.RunAllButton.Enable = 'off'; app.RunSelectedButton.Enable = 'off'; app.CancelButton.Enable = 'on';
            app.RemoveButton.Enable = 'off'; app.ClearButton.Enable = 'off'; % indices below would go stale if the list changed mid-run
            app.startNextInQueue();
        end

        function startNextInQueue(app)
            app.BatchQueuePos = app.BatchQueuePos + 1;
            if app.CancelRequested || app.BatchQueuePos > numel(app.BatchQueueIndices)
                app.finishBatch();
                return
            end
            idx = app.BatchQueueIndices(app.BatchQueuePos);
            app.CurrentSubjIdx = idx;
            app.CurrentStartTic = tic;
            app.LogFilePos = 0;
            app.LogPendingPartial = '';
            app.resetChecklist();
            app.RunStatusLabel.Text = sprintf('Subject %d/%d: %s', app.BatchQueuePos, numel(app.BatchQueueIndices), app.Subjects(idx).ID);
            app.launchSubjectProcess(idx);
        end

        function launchSubjectProcess(app, idx)
            % Launches lib/pipeline/run_subject_worker.m for this subject as a
            % detached background process. HOW it's launched depends on isdeployed:
            %   - interpreted/dev: a "matlab -batch" process calling the worker
            %     function directly (MATLAB is installed+licensed here).
            %   - compiled standalone .exe: no matlab.exe exists on the target
            %     machine, so the app relaunches ITSELF with a "--worker" flag;
            %     APTwGUI.m's entry point dispatches that straight to
            %     run_subject_worker instead of opening the GUI.
            subj = app.Subjects(idx);
            cfg = app.buildCfg();
            if ~isfolder(app.RunWorkDir), mkdir(app.RunWorkDir); end
            stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
            base = fullfile(app.RunWorkDir, sprintf('%s_%s', matlab.lang.makeValidName(subj.ID), stamp));
            files = struct('argsFile', [base '_args.mat'], ...
                'log', [base '_log.txt'], 'pid', [base '_pid.txt'], 'done', [base '_done.txt']);
            app.CurrentRunFiles = files;

            subjPath = subj.Path; binFolder = app.BinFolder; %#ok<NASGU>
            pidFile = files.pid; logFile = files.log; doneFile = files.done; %#ok<NASGU>
            save(files.argsFile, 'cfg', 'subjPath', 'binFolder', 'pidFile', 'logFile', 'doneFile');

            if isdeployed
                cmdStr = sprintf('start "" /B "%s" --worker "%s"', app.SelfExePath, files.argsFile);
            else
                cmdStr = sprintf('start "" /B "%s" -batch "run_subject_worker(''%s'')"', ...
                    fullfile(matlabroot, 'bin', 'matlab.exe'), files.argsFile);
            end
            [status, out] = system(cmdStr);
            if status ~= 0
                app.appendLog(sprintf('Failed to launch background process for %s: %s', subj.ID, out));
            end
            app.appendLog(sprintf('===== %s : started (background process, PID written to %s) =====', subj.ID, files.pid));

            app.ensureBatchTimer();
        end

        function ensureBatchTimer(app)
            if isempty(app.BatchTimer) || ~isvalid(app.BatchTimer)
                app.BatchTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.75, ...
                    'TimerFcn', @(~,~) app.onPollTick(), 'BusyMode', 'drop', 'Name', 'APTwGUI_BatchPoll');
            end
            if strcmp(app.BatchTimer.Running, 'off')
                start(app.BatchTimer);
            end
        end

        function onPollTick(app)
            if app.CurrentSubjIdx == 0 || ~isvalid(app.UIFigure), return; end
            idx = app.CurrentSubjIdx;
            files = app.CurrentRunFiles;

            if isfile(files.log)
                fid = fopen(files.log, 'r');
                if fid > 0
                    fseek(fid, app.LogFilePos, 'bof');
                    newText = fread(fid, Inf, '*char')';
                    app.LogFilePos = ftell(fid);
                    fclose(fid);
                    app.tailLogText(newText);
                end
            end

            if app.CancelRequested
                app.flushPendingPartial();
                app.killCurrentProcess();
                app.Subjects(idx).Status = 'Cancelled';
                app.appendLog(sprintf('===== %s : cancelled by user =====', app.Subjects(idx).ID));
                app.refreshSubjectTable();
                app.CurrentSubjIdx = 0;
                app.finishBatch();
                return
            end

            if isfile(files.done)
                app.flushPendingPartial();
                txt = strtrim(fileread(files.done));
                if startsWith(txt, 'OK')
                    app.Subjects(idx).Status = 'Done';
                    app.Subjects(idx).Error = '';
                    app.setAllStages('done');
                else
                    app.Subjects(idx).Status = 'FAILED';
                    app.Subjects(idx).Error = txt;
                    app.BatchNFailed = app.BatchNFailed + 1;
                    app.appendLog(sprintf('===== %s : %s =====', app.Subjects(idx).ID, txt));
                end
                app.refreshSubjectTable();
                app.CurrentSubjIdx = 0;
                app.startNextInQueue();
                return
            end

            elapsed = toc(app.CurrentStartTic);
            app.Subjects(idx).Status = sprintf('Running... (%ds)', round(elapsed));
            app.refreshSubjectTable();
        end

        function tailLogText(app, newText)
            % Buffers any trailing partial (not yet newline-terminated) line across
            % polls, so a "__STAGE__:..." marker split across two reads is never
            % misparsed, and visible log lines are never shown half-written.
            if isempty(newText), return; end
            combined = [app.LogPendingPartial, newText];
            lastNL = find(combined == newline, 1, 'last');
            if isempty(lastNL)
                app.LogPendingPartial = combined;
                return
            end
            completeText = combined(1:lastNL);
            app.LogPendingPartial = combined(lastNL+1:end);
            app.processCompleteLines(completeText);
        end

        function flushPendingPartial(app)
            if ~isempty(app.LogPendingPartial)
                app.processCompleteLines(app.LogPendingPartial);
                app.LogPendingPartial = '';
            end
        end

        function processCompleteLines(app, txt)
            % Splits complete (newline-terminated) text into lines, applies any
            % "__STAGE__:..." sentinel lines to the checklist, and appends
            % everything else to the visible log (the sentinels themselves are
            % implementation plumbing, not meant for the user to read).
            lns = strsplit(txt, newline);
            keep = true(1, numel(lns));
            for i = 1:numel(lns)
                tok = strtrim(lns{i});
                if startsWith(tok, '__STAGE__:')
                    keep(i) = false;
                    app.applyStageMarker(tok);
                end
            end
            visible = strjoin(lns(keep), newline);
            app.appendLog(visible);
        end

        function applyStageMarker(app, tok)
            markerMap = { ...
                '__STAGE__:PREPARE_START', 1, 'active'
                '__STAGE__:PREPARE_DONE',  1, 'done'
                '__STAGE__:SEGMENT_START', 2, 'active'
                '__STAGE__:SEGMENT_DONE',  2, 'done'
                '__STAGE__:WASABI_START',  3, 'active'
                '__STAGE__:WASABI_DONE',   3, 'done'
                '__STAGE__:PROCESS_START', 4, 'active'
                '__STAGE__:PROCESS_DONE',  4, 'done'
                '__STAGE__:EXPORT_START',  5, 'active'
                '__STAGE__:EXPORT_DONE',   5, 'done'};
            row = find(strcmp(markerMap(:, 1), tok), 1);
            if isempty(row), return; end
            app.StageStates{markerMap{row, 2}} = markerMap{row, 3};
            app.updateChecklistDisplay();
        end

        function resetChecklist(app)
            app.StageStates = repmat({'pending'}, 1, numel(app.StageNames));
            app.updateChecklistDisplay();
        end

        function setAllStages(app, state)
            app.StageStates = repmat({state}, 1, numel(app.StageNames));
            app.updateChecklistDisplay();
        end

        function updateChecklistDisplay(app)
            lines = cell(1, numel(app.StageNames));
            for i = 1:numel(app.StageNames)
                switch app.StageStates{i}
                    case 'done',   mark = '[x]';
                    case 'active', mark = '[~]';
                    otherwise,     mark = '[ ]';
                end
                lines{i} = sprintf('%s %s', mark, app.StageNames{i});
            end
            app.ChecklistLabel.Text = lines;
        end

        function killCurrentProcess(app)
            pidFile = app.CurrentRunFiles.pid;
            if isfile(pidFile)
                try
                    pidStr = strtrim(fileread(pidFile));
                    if ~isempty(pidStr)
                        system(sprintf('taskkill /PID %s /T /F', pidStr));
                    end
                catch
                end
            end
        end

        function finishBatch(app)
            if ~isempty(app.BatchTimer) && isvalid(app.BatchTimer) && strcmp(app.BatchTimer.Running, 'on')
                stop(app.BatchTimer);
            end
            app.IsRunning = false;
            app.CurrentSubjIdx = 0;
            app.RunAllButton.Enable = 'on'; app.RunSelectedButton.Enable = 'on'; app.CancelButton.Enable = 'off';
            app.RemoveButton.Enable = 'on'; app.ClearButton.Enable = 'on';
            if app.CancelRequested
                app.RunStatusLabel.Text = sprintf('Cancelled. %d processed, %d failed before stopping.', max(app.BatchQueuePos - 1, 0), app.BatchNFailed);
            else
                app.RunStatusLabel.Text = sprintf('Idle. Last batch: %d processed, %d failed.', numel(app.BatchQueueIndices), app.BatchNFailed);
            end
            app.refreshViewerSubjectList();
        end
    end

    % =====================================================================
    %  logging
    % =====================================================================
    methods (Access = private)
        function appendLog(app, txt)
            if isempty(txt), return; end
            existing = app.LogTextArea.Value;
            if ischar(existing), existing = {existing}; end
            newLines = strsplit(txt, newline);
            app.LogTextArea.Value = [existing(:); newLines(:)];
            scroll(app.LogTextArea, 'bottom');
            drawnow limitrate;
        end

        function onClearLog(app)
            app.LogTextArea.Value = {''};
        end
    end

    % =====================================================================
    %  results viewer
    % =====================================================================
    methods (Access = private)
        function refreshViewerSubjectList(app)
            ids = {}; paths = {};
            for i = 1:numel(app.Subjects)
                [~, id] = fileparts(app.Subjects(i).Path);
                resultsFile = fullfile(app.Subjects(i).Path, 'Zeval', [id '_APTw_results.mat']);
                if isfile(resultsFile)
                    ids{end+1} = id; %#ok<AGROW>
                    paths{end+1} = app.Subjects(i).Path; %#ok<AGROW>
                end
            end
            if isempty(ids)
                app.SubjectDropDown.Items = {'(none processed yet)'};
                app.SubjectDropDown.ItemsData = {''};
                app.CurrentViewerResults = [];
            else
                prevValue = app.SubjectDropDown.ItemsData;
                if isempty(prevValue), prevValue = {''}; end
                app.SubjectDropDown.Items = ids;
                app.SubjectDropDown.ItemsData = paths;
                if ~ischar(prevValue) && ismember(prevValue{1}, paths)
                    app.SubjectDropDown.Value = prevValue{1};
                else
                    app.SubjectDropDown.Value = paths{1};
                end
                app.onSubjectChanged();
            end
        end

        function onSubjectChanged(app)
            path = app.SubjectDropDown.Value;
            if isempty(path)
                app.CurrentViewerResults = [];
                return
            end
            [~, id] = fileparts(path);
            resultsFile = fullfile(path, 'Zeval', [id '_APTw_results.mat']);
            if ~isfile(resultsFile)
                app.CurrentViewerResults = [];
                return
            end
            app.CurrentViewerResults = load(resultsFile);
            app.CurrentViewerSpectra = [];
            app.CurrentViewerSpectraSubject = '';

            avail = {'APTw', 'APTw_rex', 'APTw_noB1', 'APTw_rex_noB1', 'B1map', 'dB0map'};
            avail = avail(isfield(app.CurrentViewerResults.maps, avail));
            if isempty(avail), avail = {'APTw'}; end
            app.MapDropDown.Items = avail;
            app.CompareMapDropDown.Items = avail;
            if ~ismember(app.MapDropDown.Value, avail), app.MapDropDown.Value = avail{1}; end
            if ~ismember(app.CompareMapDropDown.Value, avail)
                app.CompareMapDropDown.Value = avail{min(2, numel(avail))};
            end

            nSlices = max(1, size(app.CurrentViewerResults.maps.(app.MapDropDown.Value), 3));
            if nSlices > 1
                app.SliceSlider.Limits = [1 nSlices];
                ticks = 1:nSlices;
            else
                app.SliceSlider.Limits = [1 1.0001]; % uislider rejects Limits(1)==Limits(2)
                ticks = 1;
            end
            % Tick marks (no labels - the "Slice X/N" label beside the slider already
            % shows the current slice, and per-integer labels get cut off/overlap).
            app.SliceSlider.MajorTicks = ticks;
            app.SliceSlider.MajorTickLabels = repmat({''}, 1, numel(ticks));
            app.SliceSlider.MinorTicks = [];
            app.SliceSlider.Value = ceil(nSlices / 2);

            app.onResetWindow(); % also triggers updateMainDisplay
        end

        function onSliceSliderChanged(app)
            % Snap to the nearest integer slice - dragging the slider can otherwise
            % leave its thumb (and internally, Value) at a fractional position.
            app.SliceSlider.Value = round(app.SliceSlider.Value);
            app.updateMainDisplay();
        end

        function onScrollWheel(app, evt)
            % Mouse-wheel slice scrolling while the Results Viewer tab is showing.
            % Setting WindowScrollWheelFcn captures scroll events figure-wide (there
            % is no per-component scroll hook in uifigure), so native scrolling of
            % other components (e.g. the log text area) is a minor, accepted trade-off.
            if isempty(app.CurrentViewerResults), return; end
            if isempty(app.TabGroup.SelectedTab) || app.TabGroup.SelectedTab ~= app.ViewerTab, return; end
            limits = app.SliceSlider.Limits;
            step = -sign(evt.VerticalScrollCount); % scroll up -> next slice
            if step == 0, return; end
            newVal = max(limits(1), min(floor(limits(2)), round(app.SliceSlider.Value) + step));
            if newVal == round(app.SliceSlider.Value), return; end
            app.SliceSlider.Value = newVal;
            app.updateMainDisplay();
        end

        function onCompareToggled(app)
            if app.CompareCheckBox.Value
                app.DisplayGrid.ColumnWidth = {'1x', '1x'};
                app.CompareAxes.Visible = 'on';
                app.CompareMapDropDown.Enable = 'on';
            else
                app.DisplayGrid.ColumnWidth = {'1x', 0};
                app.CompareAxes.Visible = 'off';
                app.CompareMapDropDown.Enable = 'off';
            end
            app.updateMainDisplay();
        end

        function onResetWindow(app)
            S = app.CurrentViewerResults;
            mapName = app.MapDropDown.Value;
            if isempty(S) || ~isfield(S.maps, mapName)
                app.updateMainDisplay();
                return
            end
            vol = S.maps.(mapName);
            scale = 1; if startsWith(mapName, 'APTw'), scale = 100; end
            seg = S.qc.Segment > 0;
            vals = vol * scale;
            nz = min(size(vals, 3), size(seg, 3));
            vals = vals(:, :, 1:nz); segv = seg(:, :, 1:nz);
            vals = vals(segv & isfinite(vals));
            w = pctwin(vals);
            app.WMinSpinner.Value = w(1);
            app.WMaxSpinner.Value = w(2);
            app.updateMainDisplay();
        end

        function updateMainDisplay(app)
            app.renderMap(app.MainAxes, app.MapDropDown.Value, true);
            if app.CompareCheckBox.Value
                app.renderMap(app.CompareAxes, app.CompareMapDropDown.Value, false);
            end
            S = app.CurrentViewerResults;
            if ~isempty(S)
                nSlices = size(S.maps.(app.MapDropDown.Value), 3);
                app.SliceLabel.Text = sprintf('Slice %d / %d', round(app.SliceSlider.Value), nSlices);
            end
            app.updateHistogramAndStats();
        end

        function renderMap(app, ax, mapName, isMain)
            S = app.CurrentViewerResults;
            cla(ax);
            if isempty(S) || isempty(mapName) || ~isfield(S.maps, mapName)
                title(ax, '');
                return
            end
            vol = S.maps.(mapName);
            scale = 1; if startsWith(mapName, 'APTw'), scale = 100; end
            nSlices = size(vol, 3);
            slice = max(1, min(round(app.SliceSlider.Value), nSlices));
            img = permute(vol(:, :, slice), [2 1]) * scale;
            segSlice = min(slice, size(S.qc.Segment, 3));
            seg = permute(S.qc.Segment(:, :, segSlice), [2 1]) > 0;
            img(~seg) = NaN;

            w = [app.WMinSpinner.Value, app.WMaxSpinner.Value];
            if ~isfinite(w(1)) || ~isfinite(w(2)) || w(2) <= w(1), w = pctwin(img(:)); end

            h = imagesc(ax, img, w);
            set(h, 'AlphaData', ~isnan(img));
            if isMain
                h.ButtonDownFcn = @(~, evt) app.onAxesClicked(evt);
            end
            axis(ax, 'image'); ax.XTick = []; ax.YTick = [];
            colormap(ax, app.currentColormapArray(w));
            colorbar(ax);
            label = mapName; if scale == 100, label = [label ' (%)']; end
            title(ax, sprintf('%s - slice %d/%d', strrep(label, '_', '\_'), slice, nSlices));
        end

        function cmap = currentColormapArray(app, w)
            switch app.ColormapDropDown.Value
                case 'Diverging (blue-white-red)'
                    cmap = bluewhitered(w);
                case 'Gray'
                    cmap = gray(256);
                otherwise
                    cmap = parula(256);
            end
        end

        function updateHistogramAndStats(app)
            S = app.CurrentViewerResults;
            mapName = app.MapDropDown.Value;
            cla(app.HistAxes);
            if isempty(S) || ~isfield(S.maps, mapName)
                app.StatsTextArea.Value = {''};
                return
            end
            vol = S.maps.(mapName);
            scale = 1; if startsWith(mapName, 'APTw'), scale = 100; end
            slice = max(1, min(round(app.SliceSlider.Value), size(vol, 3)));
            segSlice = min(slice, size(S.qc.Segment, 3));

            sliceVals = vol(:, :, slice) * scale;
            sliceSeg  = S.qc.Segment(:, :, segSlice) > 0;
            sliceVals = sliceVals(sliceSeg & isfinite(sliceVals));

            allVals = vol * scale;
            nz = min(size(allVals, 3), size(S.qc.Segment, 3));
            allSeg = S.qc.Segment(:, :, 1:nz) > 0;
            allVals = allVals(:, :, 1:nz);
            allVals = allVals(allSeg & isfinite(allVals));

            % Bin range: the current display window, not raw min/max - a handful of
            % extreme outlier voxels (e.g. a badly-fit B1/B0 voxel right at the mask
            % edge) would otherwise stretch the x-axis out to a meaningless range
            % with everything else crushed into a single bin near zero.
            binLimits = [app.WMinSpinner.Value, app.WMaxSpinner.Value];
            if ~isfinite(binLimits(1)) || ~isfinite(binLimits(2)) || binLimits(2) <= binLimits(1)
                binLimits = pctwin([allVals; sliceVals]);
            end

            if ~isempty(allVals)
                histogram(app.HistAxes, allVals, 60, 'BinLimits', binLimits, 'FaceAlpha', 0.4, 'DisplayName', 'all slices');
                hold(app.HistAxes, 'on');
            end
            if ~isempty(sliceVals)
                histogram(app.HistAxes, sliceVals, 60, 'BinLimits', binLimits, 'FaceAlpha', 0.7, 'DisplayName', 'this slice');
            end
            hold(app.HistAxes, 'off');
            app.HistAxes.XLim = binLimits;
            legend(app.HistAxes, 'Location', 'best');

            lines = {};
            if ~isempty(sliceVals)
                lines{end+1} = sprintf('This slice:  n=%d, mean=%+.3f, median=%+.3f', numel(sliceVals), mean(sliceVals), median(sliceVals));
            else
                lines{end+1} = 'This slice: no in-mask voxels';
            end
            if ~isempty(allVals)
                wAll = pctwin(allVals);
                lines{end+1} = sprintf('All slices:  n=%d, mean=%+.3f, median=%+.3f', numel(allVals), mean(allVals), median(allVals));
                lines{end+1} = sprintf('2-98%% range (all slices): [%.3f, %.3f]', wAll(1), wAll(2));
            end
            app.StatsTextArea.Value = lines;
        end

        function onAxesClicked(app, evt)
            S = app.CurrentViewerResults;
            if isempty(S), return; end
            pt = evt.IntersectionPoint;
            ii = round(pt(1)); jj = round(pt(2)); kk = round(app.SliceSlider.Value);
            segSz = size(S.qc.Segment);
            if ii < 1 || jj < 1 || kk < 1 || ii > segSz(1) || jj > segSz(2) || kk > segSz(3)
                return
            end
            app.showSpectrumAt(ii, jj, kk);
        end

        function showSpectrumAt(app, ii, jj, kk)
            S = app.CurrentViewerResults;
            path = app.SubjectDropDown.Value;
            [~, id] = fileparts(path);
            if isempty(app.CurrentViewerSpectra) || ~strcmp(app.CurrentViewerSpectraSubject, path)
                specFile = fullfile(path, 'Zeval', [id '_APTw_full_Zspectra.mat']);
                if ~isfile(specFile)
                    uialert(app.UIFigure, 'No full-Z-spectrum file for this subject (needed for the click-to-inspect view).', 'Not available');
                    return
                end
                d = uiprogressdlg(app.UIFigure, 'Title', 'Loading', ...
                    'Message', 'Loading full Z-spectrum data (once per subject)...', 'Indeterminate', 'on');
                cleanupObj = onCleanup(@() close(d)); %#ok<NASGU>
                app.CurrentViewerSpectra = load(specFile, 'Z_corrExt', 'Z_corrExt_denoised');
                app.CurrentViewerSpectraSubject = path;
            end
            w = S.info.acquisitionParams.SEQ.w;
            raw = squeeze(app.CurrentViewerSpectra.Z_corrExt(ii, jj, kk, :));
            den = squeeze(app.CurrentViewerSpectra.Z_corrExt_denoised(ii, jj, kk, :));
            cla(app.SpectrumAxes);
            plot(app.SpectrumAxes, w, raw, 'o-', 'DisplayName', 'B0-corrected'); hold(app.SpectrumAxes, 'on');
            plot(app.SpectrumAxes, w, den, '.-', 'DisplayName', 'denoised'); hold(app.SpectrumAxes, 'off');
            xlabel(app.SpectrumAxes, 'offset (ppm)'); ylabel(app.SpectrumAxes, 'Z (normalized)');
            legend(app.SpectrumAxes, 'Location', 'best');
            title(app.SpectrumAxes, sprintf('voxel (%d,%d,%d)', ii, jj, kk));
        end

        function onOpenFolder(app)
            path = app.SubjectDropDown.Value;
            if isempty(path), return; end
            zevalFolder = fullfile(path, 'Zeval');
            if ~isfolder(zevalFolder)
                uialert(app.UIFigure, 'No Zeval folder for this subject yet.', 'Not found');
                return
            end
            if ispc
                winopen(zevalFolder);
            else
                uialert(app.UIFigure, zevalFolder, 'Zeval folder path');
            end
        end
    end

    % =====================================================================
    %  teardown
    % =====================================================================
    methods (Access = private)
        function onCloseRequest(app)
            if app.IsRunning
                app.killCurrentProcess(); % don't leave an orphaned background matlab.exe running
            end
            if ~isempty(app.BatchTimer) && isvalid(app.BatchTimer)
                stop(app.BatchTimer);
                delete(app.BatchTimer);
            end
            delete(app.UIFigure);
        end
    end
end
