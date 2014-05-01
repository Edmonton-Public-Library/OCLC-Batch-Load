OCLC-Batch-Load
===============

Scripts to manage OCLC batch load processes.
Description: 
This is a script that was developed at Edmonton Public Library to manage the OCLC batch load process. I hope that users will find it useful either as a script they can lightly modify to work in your envirionment, or at least as a working example of how we manage the process at EPL. 

Before beginning make sure you read through the code and make appropriate changes to pathing and the variable on line 96, which is our library ID, you will want to change this to your institutional id. Also pay close attention to types listed on 858 and 860. These are EPL types.

Instructions: 
The batch load process is fairly complicated and this script manages that complexity.

To get the usage message enter:

 oclc.pl -x

We also have a shell script that is cronned to run this script with the correct switches for producing the entire process automatically each month. I would be willing to upload that if you would like.

The script is broken down into modules that I developed to do each step as a discreet testable task including outputting catalogue records, splitting files to OCLC requirements, naming files and creating lable files, FTPing files to OCLC, and of course the 'just do it damn you' switch that does it all, after you have thoroughly tested each part of the script to your satisfaction.

ILS: 
Symphony
Versions: 
3.4.0+
Modules: 
Cataloging
System
Webcat
Platform: 
Solaris other Unix variants
