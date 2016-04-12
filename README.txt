README-xuezhou fan
 +Members
 +Xuezhou Fan(xfan7)-fanxz@icloud.com
 +Xiaojian Zhu(xzhu13)-490874727@qq.com
 +
 +In this homework I write the remote command part,including dd and rsync command, make file, and mount/umount volume.
 +
 +1.I use the parameters(EC2_BACKUP_FLAGS_SSH, EC2_BACKUP_VERBOSE, INSTANCE_ADDRESS)the other member give me, then use ssh to connect with the instance the other one created. 
 +
 +2. In this project, we can chose a specified volume or someone created by us.
 +If give us a volume id and I will check if this volume need to make file, then mount it on the instance with the path I already written. Then I will check the if the available space is enough for backup all the information. If is not, it will exit 3
 +
 +3.I use while loop in my functions, since sometimes we need wait for the internet 
 +transmission and in case last command did not work. The program will not process until make sure the last step is completed. Or in case of run into infinite loop, I set the max number to wait and check.