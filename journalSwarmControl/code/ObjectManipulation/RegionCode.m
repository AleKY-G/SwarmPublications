function RegionCode(webcamShot)
%% REGIONCODE -- preprocessing for block pushing experiment
% Takes a snapshot from the webcam, then processes it to find
% obstacles. From these obstacles, the corners, regions, and a policy for MDP
% is calculated. It then draws the gradients, regions, and shows the grid
% view to the user.
%
% saves this data in two files:
% 1.) MDPShot.mat:
%    [movesX,movesY]  policy in X and Y  directions
%    corners,  xy locations of corners in workspace
% 2.) ThresholdMapsMac.mat:
%     transferRegion: 3D array. transferRegion(i,:,:) gives a logical
%                   array for transfer region i
%     mainRegion:    3D array. mainRegion(i,:,:) gives a logical
%                   array for main region i
%
%  requires MDPgridworldFunction.m
% ---------------------
% By Shiva Shahrokhi and Lillian Lin,  Summer 2016
% Shiva Shahrokhi <shiva.shahrokhi@gmail.com>

if nargin<1
    webcamShot = false;
end

tic;
if webcamShot
    cam = webcam(1);
    originalImage = snapshot(cam);
    %imwrite(originalImage,'KilobotTableExample.jpeg'); % to save a new image
else
    originalImage = imread('KilobotTableExample.jpeg');
end

if (ispc)  % Code to run on PC platform
    rgbIm = imcrop(originalImage,[50 10 500 400]);
else        % Code to run on Mac platform
    rgbIm = imcrop(originalImage,[345 60 1110 860]);
end

%% Obstacle Thresholds
I = rgb2hsv(rgbIm);

% Define thresholds for channel 1 based on histogram settings
% these were picked using the Color Thresholding tool
channel1Min = 0.862;
channel1Max = 0.945;

% Define thresholds for channel 2 based on histogram settings
channel2Min = 0.272;
channel2Max = 1.000;

% Define thresholds for channel 3 based on histogram settings
channel3Min = 0.000;
channel3Max = 1.000;

% Create mask based on chosen histogram thresholds
BW = (I(:,:,1) >= channel1Min ) & (I(:,:,1) <= channel1Max) & ...
    (I(:,:,2) >= channel2Min ) & (I(:,:,2) <= channel2Max) & ...
    (I(:,:,3) >= channel3Min ) & (I(:,:,3) <= channel3Max);

%% finding Obstacles
[~,L] = bwboundaries(BW, 'noholes');
stat = regionprops(L,'Centroid','Orientation','MajorAxisLength', 'Area');
area = cat(1,stat.Area);
centroids = cat(1, stat.Centroid);
orientations = cat(1, stat.Orientation);
majorLength = cat(1, stat.MajorAxisLength);
imshow(rgbIm);
hold on
obstacles = find(area > 780); %remove small objects.

%% detect Object Orientation
xlim = get(gca,'XLim');
ylim = get(gca,'YLim');
slope=zeros(size(obstacles));
offset=zeros(size(obstacles));
Tangent_offset=zeros(size(obstacles));

tipx = zeros(size(obstacles));%[tipx,tipy] are extreme edges of obstacles
tipy = zeros(size(obstacles));
for i = 1:numel(obstacles)
    tipx(i)=centroids(obstacles(i),1) + cos(orientations(obstacles(i))*pi/180)* majorLength(obstacles(i))/2.3;
    tipy(i)=centroids(obstacles(i),2) - sin(orientations(obstacles(i))*pi/180)* majorLength(obstacles(i))/2.3;
    % ensures that [tipx,tipy] is inside the workspace
    if abs(tipy(i)-ylim(1))<50||abs(tipy(i)-ylim(2))<50||abs(tipx(i)-xlim(2))<50||abs(tipx(i)-xlim(1))<50
        tipx(i)=centroids(obstacles(i),1)-cos(orientations(obstacles(i))*pi/180)* majorLength(obstacles(i))/2.3;
        tipy(i)=centroids(obstacles(i),2)+sin(orientations(obstacles(i))*pi/180)* majorLength(obstacles(i))/2.3;
    end
    %draw the extreme points and the orientation
    hold on
    plot(tipx(i), tipy(i),'*','Markersize',16,'color','white','linewidth',3);
    slope(i)=(centroids(obstacles(i),2)-tipy(i))/(centroids(obstacles(i),1)-tipx(i));
    offset(i)=-slope(i)*centroids(obstacles(i),1)+centroids(obstacles(i),2);
    Tangent_offset(i)=tipy(i)+tipx(i)*(1/slope(i));
    line([xlim(1) xlim(2)],[slope(i)*xlim(1)+offset(i) slope(i)*xlim(2)+offset(i)])
    line([xlim(1) xlim(2)],[(-1/slope(i))*xlim(1)+Tangent_offset(i) (-1/slope(i))*xlim(2)+Tangent_offset(i)])
    hold off
end

%% Map Creation
goalX = 5;  % goal position: kilobots are steered to this position
goalY = 5;
s = size(rgbIm);
numberOfSquares=30; %number of squares we want in the x direction
scale = floor(s(2)/numberOfSquares);
sizeOfMap = floor(s/scale);
map = zeros(sizeOfMap(1),sizeOfMap(2));
mainRegion = zeros(sizeOfMap(1),sizeOfMap(2),(1+size(obstacles,1)));
transferRegion = zeros(sizeOfMap(1),sizeOfMap(2),(size(obstacles,1)));

corners =[];
map(1,:) = 1;
map(:,1) = 1;
map(sizeOfMap(1),:) = 1;
map(:,sizeOfMap(2)) = 1;
hold on
%% Plot Grid
for i= 1:sizeOfMap(1)
    plot(xlim,[i*scale i*scale],'color','red')
end

for j = 1:sizeOfMap(2)
    plot([j*scale j*scale],ylim,'color',[0.6 0.6 0.6])
end
hold off

%% Determining the Main Region
RegionCount=1;

for i=1:sizeOfMap(1)         %Horizontal Grid (y-values)
    for j=1:sizeOfMap(2)     %Vertical Grid (x-values)
        for equation=1:size(slope,1)
            if ((scale/2)+j*scale)>(((scale/2)+i*scale)-offset(equation))/slope(equation)
                RegionCount=RegionCount+1;
            end
        end
        mainRegion((i),(j),RegionCount)=1;
        RegionCount=1;
    end
end
%% Determining the Transfer Region
for i=1:size(slope,1)
    lowx=xlim(1);
    highx=xlim(2);
    if abs(ylim(1)-tipy(i))<abs(ylim(2)-tipy(i)) % top is closer
        for ygrid=1:ceil(tipy(i)/scale)
            for j=1:size(slope,1)
                if i==j
                    continue;
                end
                if (((((ygrid*scale)-(scale/2))/2)-offset(j))/slope(j))-tipx(i)<0 % on left side
                    if abs(((((ygrid*scale)-(scale/2))/2)-offset(j))/slope(j)-tipx(i))<abs(lowx-tipx(i))
                        lowx=((((ygrid*scale)-(scale/2))/2)-offset(j))/slope(j);
                    end
                else % on right side
                    if abs(((((ygrid*scale)-(scale/2))/2)-offset(j))/slope(j)-tipx(i))<abs(highx-tipx(i))
                        highx=((((ygrid*scale)-(scale/2))/2)-offset(j))/slope(j);
                    end
                end
            end
            for m=ceil(lowx/scale):floor(highx/scale)
                transferRegion(ygrid,m,i)=1;
            end
        end
    else % bottom is closer
        for ygrid=floor(tipy(i)/scale):sizeOfMap(1)
            for j=1:size(slope,1)
                if i==j
                    continue;
                end
                if (((((ylim(2)+((ygrid*scale)-(scale/2)))/2)-offset(j))/slope(j))-tipx(i))<0 % on left side
                    if abs(((((ylim(2)+ ((ygrid*scale)-(scale/2)))/2)-offset(j))/slope(j))-tipx(i))<abs(lowx-tipx(i))
                        lowx=((((ylim(2)+ ((ygrid*scale)-(scale/2)))/2)-offset(j))/slope(j));
                    end
                else
                    if abs(((((ylim(2)+ ((ygrid*scale)-(scale/2)))/2)-offset(j))/slope(j))-tipx(i))<abs(highx-tipx(i))
                        highx=((((ylim(2)+ ((ygrid*scale)-(scale/2)))/2)-offset(j))/slope(j));
                    end
                end
            end
            for m=ceil(lowx/scale):floor(highx/scale)
                transferRegion(ygrid,m,i)=1;
            end
        end
    end
end
%% Remove Obstacles from Image
for obs=1:size(obstacles,1)
    for along = floor((centroids(obstacles(obs),2) + sin(orientations(obstacles(obs))*pi/180)* majorLength(obstacles(obs))/2.3)/scale) :floor((centroids(obstacles(obs),2) - sin(orientations(obstacles(obs))*pi/180)* majorLength(obstacles(obs))/2.3)/scale)
        if along<ylim(1)||along>ylim(2)
            continue;
        end
        x=floor(((along-offset(obs))/slope(obs))/scale);
        transferRegion(along,x,:)=2;
        mainRegion(along,x,:)=2;
    end
end
%% Display Regions
figure(2), imshow(transferRegion(:,:,1));
figure(3), imshow(transferRegion(:,:,2));
figure(4), imshow(mainRegion);
%% Making the walls
for i= 1:sizeOfMap(1)-1
    for j = 1:sizeOfMap(2)-1
        if sum(sum(BW( i*scale:i*scale+scale-1, j*scale:j*scale+scale-1)>0))>0
            map(i,j) = 1; %%% points the obstacles.
        end
        %         for k = 0:scale-1
        %             for l = 0:scale-1
        %                 if BW(i*scale+k, j*scale+l,1) > 0 % detect an obstacle
        %                     map(i,j) = 1; %%% points the obstacles.
        %                 end
        %             end
        %         end
    end
end

%% Finding corners
for j = 2:sizeOfMap(2)-1
    for i = 2:sizeOfMap(1)-1
        if map(i,j) ~=1
            if (map(i-1,j) == 1 && map(i,j-1) ==1) || (map(i+1,j) == 1 && map(i,j+1) ==1) ...
                    || (map(i+1,j) == 1 && map(i,j-1) ==1) ||(map(i-1,j) == 1 && map(i,j+1) ==1)
                corners = [corners; j i]; %#ok<AGROW>
            end
        end
    end
end
%% Saving the results
save('ThresholdMapsMac','transferRegion','mainRegion');

%% Policy Iteration Code
[probability, movesX, movesY] = MDPgridworldFunction(map,goalX,goalY); %#ok<NASGU,ASGLU>
save('MazeMap', 'movesX', 'movesY','corners');
%% (*turns off the camera*)
if webcamShot
    clear('cam');
end

