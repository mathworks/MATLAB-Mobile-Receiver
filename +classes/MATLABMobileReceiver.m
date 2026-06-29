classdef MATLABMobileReceiver < matlab.System
    % MATLABMobileReceiver Read mobile device sensor and camera data.
    % Enable any combination of acceleration, orientation, angular velocity,
    % position, magnetic field, and camera output. Frequency controls the
    % sensor sample rate in Hz.

    % Public, tunable properties
    properties (Nontunable)
        AccelerationEnabled (1,1) logical = true % Acceleration
        OrientationEnabled (1,1) logical = false  % Orientation
        AngularVelocityEnabled (1,1) logical = false % Angular Velocity
        PositionEnabled (1,1) logical = false % Position (Latitude, Longitude, Altitude)
        MagneticFieldEnabled (1,1) logical = false % Magnetic Field

        CameraSelected (1,1) string {mustBeMember(CameraSelected,["back","front"])} = "back"; % Camera
        FPS (1,1) double = 1 % FPS
        Frequency (1,1) double = 10 % Frequency (Hz)
    end

    properties (Nontunable)
        CameraEnabled (1,1) logical = false % Enabled
    end

    properties (Constant, Access = private)
        DefaultVector (1,3) double = [0 0 0]
        VectorOutputSize (1,2) double = [1 3]
        CameraImageSize (1,3) double = [640 480 3]
        MinFPS (1,1) double = 0
        MaxFPS (1,1) double = 10
        MinFrequency (1,1) double = 1
        MaxFrequency (1,1) double = 100
    end

    % Pre-computed constants or internal states
    properties (Access = private)
        mdev
        cam
        fpsDivider
        fpsDividerCounter
        camImage
    end

    methods
        function obj = MATLABMobileReceiver(varargin)
            setProperties(obj,nargin,varargin{:});
            obj.camImage = obj.createDefaultImage();
        end

        function set.FPS(obj, value)
            mustBeBetween(value, obj.MinFPS, obj.MaxFPS);
            obj.FPS = value;
        end

        function set.Frequency(obj, value)
            mustBeBetween(value, obj.MinFrequency, obj.MaxFrequency);
            obj.Frequency = value;
        end
    end

    methods (Access = protected)
        function setupImpl(obj)
            try
                obj.mdev = mobiledev;
            catch ME
                warning("MATLABMobileReceiver:mobiledevNotAvailable", ...
                    "mobiledev creation failed: %s", ME.message);
                obj.mdev = [];
            end

            if ~isempty(obj.mdev)
                obj.mdev.AccelerationSensorEnabled = obj.AccelerationEnabled;
                obj.mdev.OrientationSensorEnabled = obj.OrientationEnabled;
                obj.mdev.PositionSensorEnabled = obj.PositionEnabled;
                obj.mdev.MagneticSensorEnabled = obj.MagneticFieldEnabled;
                obj.mdev.AngularVelocitySensorEnabled = obj.AngularVelocityEnabled;

                if obj.CameraEnabled
                    try
                        obj.cam = obj.mdev.camera(obj.CameraSelected);
                    catch ME
                        warning("MATLABMobileReceiver:cameraNotAvailable", ...
                            "Camera creation failed: %s", ME.message);
                        obj.cam = [];
                    end
                end
                obj.mdev.SampleRate = obj.Frequency;

                if obj.AccelerationEnabled || obj.OrientationEnabled || obj.PositionEnabled || ...
                        obj.AngularVelocityEnabled || obj.MagneticFieldEnabled
                    obj.mdev.Logging = true;
                end
            end

            if obj.FPS > 0
                obj.fpsDivider = obj.Frequency / obj.FPS;
            else
                obj.fpsDivider = Inf;
            end
            obj.fpsDividerCounter = 0;
        end

        function [out1, out2, out3, out4, out5, out6] = stepImpl(obj, varargin)
            % Default placeholders (unused outputs can be left empty)
            out1 = [];
            out2 = [];
            out3 = [];
            out4 = [];
            out5 = [];
            out6 = [];

            shoot = false;
            if ~isempty(varargin)
                shoot = varargin{1};
            end

            % Collect enabled outputs in compile-time ordering.
            outs = cell(1,6);
            outputIndex = 1;
            defaultVector = obj.DefaultVector;

            if obj.AccelerationEnabled
                outs{outputIndex} = obj.readVectorOrDefault("Acceleration", defaultVector);
                outputIndex = outputIndex + 1;
            end

            if obj.OrientationEnabled
                outs{outputIndex} = obj.readVectorOrDefault("Orientation", defaultVector);
                outputIndex = outputIndex + 1;
            end

            if obj.AngularVelocityEnabled
                outs{outputIndex} = obj.readVectorOrDefault("AngularVelocity", defaultVector);
                outputIndex = outputIndex + 1;
            end

            if obj.PositionEnabled
                position = defaultVector;
                if ~isempty(obj.mdev)
                    latitude = obj.mdev.Latitude;
                    longitude = obj.mdev.Longitude;
                    altitude = obj.mdev.Altitude;
                    if ~isempty(latitude) && ~isempty(longitude) && ~isempty(altitude)
                        position = [latitude, longitude, altitude];
                    end
                end
                outs{outputIndex} = position;
                outputIndex = outputIndex + 1;
            end

            if obj.MagneticFieldEnabled
                outs{outputIndex} = obj.readVectorOrDefault("MagneticField", defaultVector);
                outputIndex = outputIndex + 1;
            end

            if obj.CameraEnabled
                if ~isempty(obj.cam)
                    obj.fpsDividerCounter = obj.fpsDividerCounter + 1;
                    shouldCaptureFrame = (obj.FPS == 0 && shoot) || ...
                        (obj.FPS > 0 && obj.fpsDividerCounter >= obj.fpsDivider);

                    if shouldCaptureFrame
                        obj.camImage = obj.cam.snapshot("immediate");
                        obj.fpsDividerCounter = 0;
                    end
                end

                outs{outputIndex} = obj.camImage;
            end

            % Assign collected outputs into the return variables.
            if numel(outs) >= 1, out1 = outs{1}; end
            if numel(outs) >= 2, out2 = outs{2}; end
            if numel(outs) >= 3, out3 = outs{3}; end
            if numel(outs) >= 4, out4 = outs{4}; end
            if numel(outs) >= 5, out5 = outs{5}; end
            if numel(outs) >= 6, out6 = outs{6}; end
        end

        function resetImpl(obj)
            obj.fpsDividerCounter = 0;
            obj.camImage = obj.createDefaultImage();
        end

        function releaseImpl(obj)
            try
                if ~isempty(obj.mdev) && isvalid(obj.mdev)
                    obj.mdev.Logging = false;
                end
            catch
                % Ignore cleanup errors from a disconnected mobile device.
            end
            try
                if ~isempty(obj.cam)
                    obj.cam = [];
                end
            catch
                % Ignore cleanup errors from an unavailable camera.
            end
            obj.mdev = [];
        end

        function num = getNumInputsImpl(obj)
            % Define total number of inputs for system with optional inputs
            if obj.CameraEnabled && obj.FPS == 0
                num = 1;
            else
                num = 0;
            end
        end

        function names = getInputNamesImpl(obj)
            if obj.CameraEnabled && obj.FPS == 0
                names = "Shoot";
            else
                names = strings(1,0);
            end
        end

        function validateInputsImpl(obj, varargin)
            if obj.CameraEnabled && obj.FPS == 0
                if isempty(varargin)
                    error("MATLABMobileReceiver:missingShootInput", ...
                        "Shoot input is required when Camera is enabled and FPS is 0.");
                end

                validateattributes(varargin{1}, {'logical'}, {'scalar'}, ...
                    "MATLABMobileReceiver", "Shoot");
            end
        end

        function flag = isInactivePropertyImpl(obj, propertyName)
            cameraProperties = ["CameraSelected", "FPS"];
            flag = ~obj.CameraEnabled && any(propertyName == cameraProperties);
        end

        function names = getOutputNamesImpl(obj)
            names = strings(1,6);
            outputIndex = 1;
            if obj.AccelerationEnabled
                names(outputIndex) = "Acceleration";
                outputIndex = outputIndex + 1;
            end
            if obj.OrientationEnabled
                names(outputIndex) = "Orientation";
                outputIndex = outputIndex + 1;
            end
            if obj.AngularVelocityEnabled
                names(outputIndex) = "AngularVelocity";
                outputIndex = outputIndex + 1;
            end
            if obj.PositionEnabled
                names(outputIndex) = "Position";
                outputIndex = outputIndex + 1;
            end
            if obj.MagneticFieldEnabled
                names(outputIndex) = "Magnetic Field";
                outputIndex = outputIndex + 1;
            end
            if obj.CameraEnabled
                names(outputIndex) = "Image";
                outputIndex = outputIndex + 1;
            end
            names(outputIndex:end) = [];
        end

        function [out1, out2, out3, out4, out5, out6] = getOutputSizeImpl(obj)
            % Build a cell/array for the enabled outputs in the same order
            sizes = cell(1,6);
            outputIndex = 1;
            if obj.AccelerationEnabled, sizes{outputIndex} = obj.VectorOutputSize; outputIndex = outputIndex + 1; end
            if obj.OrientationEnabled, sizes{outputIndex} = obj.VectorOutputSize; outputIndex = outputIndex + 1; end
            if obj.AngularVelocityEnabled, sizes{outputIndex} = obj.VectorOutputSize; outputIndex = outputIndex + 1; end
            if obj.PositionEnabled, sizes{outputIndex} = obj.VectorOutputSize; outputIndex = outputIndex + 1; end
            if obj.MagneticFieldEnabled, sizes{outputIndex} = obj.VectorOutputSize; outputIndex = outputIndex + 1; end
            if obj.CameraEnabled, sizes{outputIndex} = obj.CameraImageSize; end

            out1 = sizes{1};
            out2 = sizes{2};
            out3 = sizes{3};
            out4 = sizes{4};
            out5 = sizes{5};
            out6 = sizes{6};
        end

        function [out1, out2, out3, out4, out5, out6] = getOutputDataTypeImpl(obj)
            dataTypes = strings(1,6);
            outputIndex = 1;
            if obj.AccelerationEnabled, dataTypes(outputIndex) = "double"; outputIndex = outputIndex + 1; end
            if obj.OrientationEnabled, dataTypes(outputIndex) = "double"; outputIndex = outputIndex + 1; end
            if obj.AngularVelocityEnabled, dataTypes(outputIndex) = "double"; outputIndex = outputIndex + 1; end
            if obj.PositionEnabled, dataTypes(outputIndex) = "double"; outputIndex = outputIndex + 1; end
            if obj.MagneticFieldEnabled, dataTypes(outputIndex) = "double"; outputIndex = outputIndex + 1; end
            if obj.CameraEnabled, dataTypes(outputIndex) = "uint8"; end

            out1 = dataTypes(1);
            out2 = dataTypes(2);
            out3 = dataTypes(3);
            out4 = dataTypes(4);
            out5 = dataTypes(5);
            out6 = dataTypes(6);
        end

        function [out1, out2, out3, out4, out5, out6] = isOutputComplexImpl(~)
            % Return true for each output port with complex data
            out1 = false;
            out2 = false;
            out3 = false;
            out4 = false;
            out5 = false;
            out6 = false;
        end

        function [out1, out2, out3, out4, out5, out6] = isOutputFixedSizeImpl(~)
            % Return true for each output port with fixed size
            out1 = true;
            out2 = true;
            out3 = true;
            out4 = true;
            out5 = true;
            out6 = true;
        end

        function num = getNumOutputsImpl(obj)
            num = double(obj.AccelerationEnabled) + ...
                double(obj.OrientationEnabled) + ...
                double(obj.AngularVelocityEnabled) + ...
                double(obj.PositionEnabled) + ...
                double(obj.MagneticFieldEnabled) + ...
                double(obj.CameraEnabled);
        end

        function icon = getIconImpl(~)
            % Define icon for System block
            iconPath = fullfile(fileparts(mfilename("fullpath")), "MATLABMobileReceiver.svg");
            icon = matlab.system.display.Icon(iconPath);
        end

        function sts = getSampleTimeImpl(obj)
            sts = createSampleTime(obj, Type="Discrete", SampleTime=1/obj.Frequency);
        end

    end

    methods (Access = private)
        function value = readVectorOrDefault(obj, propertyName, defaultVector)
            value = defaultVector;
            if isempty(obj.mdev)
                return
            end

            value = obj.mdev.(char(propertyName));
            if isempty(value)
                value = defaultVector;
            end
        end

        function image = createDefaultImage(obj)
            image = zeros(obj.CameraImageSize, "uint8");
        end
    end

    methods (Static, Access = protected)
        function header = getHeaderImpl
            header = matlab.system.display.Header(mfilename("class"), ...
                Title="MATLAB Mobile Receiver", ...
                Text="Read mobile device sensor and camera data.<br>" + ...
                "Enable any combination of acceleration, orientation, angular velocity, " + ...
                "position, magnetic field, and camera output. Frequency controls the " + ...
                "sensor sample rate in Hz.");
        end

        function group = getPropertyGroupsImpl
            % Define property section(s) for System block dialog
            props = {'AccelerationEnabled', 'OrientationEnabled', 'AngularVelocityEnabled', ...
                'PositionEnabled', 'MagneticFieldEnabled', 'Frequency'};
            sec1 = matlab.system.display.Section(Title="Mobile Sensors", ...
                PropertyList=props);
            sec2 = matlab.system.display.Section(Title="Camera", ...
                PropertyList={'CameraEnabled', 'CameraSelected', 'FPS'}, ...
                Description="FPS = frames per second; set to 0 to use external Shoot trigger.");

            group = [sec1 sec2];
        end

        function simMode = getSimulateUsingImpl
            simMode = "Interpreted execution";
        end

        function flag = showSimulateUsingImpl
            % Return false if simulation mode hidden in System block dialog
            flag = false;
        end
    end
end
