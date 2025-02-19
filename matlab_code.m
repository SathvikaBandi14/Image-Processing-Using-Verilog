img = imread('parrots.jpeg'); % Load an image
imshow(img);
imwrite(img, 'parrots.bmp'); % Save as BMP
bmp=imread('parrots.bmp');
%384x256
k=1;
for i=256:-1:1 % image is written from the topmost row to the bottom row
for j=1:384 %image is written from left to right
hex(k)=bmp(i,j,1); %red component of pixel
hex(k+1)=bmp(i,j,2);% green component of pixel
hex(k+2)=bmp(i,j,3);%blue component of pixel
k=k+3;
end
end
fid = fopen('parrots.hex', 'wt');
fprintf(fid, '%x\n', hex);
disp('Text file write done');
disp(' ');
fclose(fid);