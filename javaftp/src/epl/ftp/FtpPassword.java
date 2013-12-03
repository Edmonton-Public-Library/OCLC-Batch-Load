/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package epl.ftp;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.net.Socket;
import java.net.UnknownHostException;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 *
 * @author andrew
 */
public class FtpPassword
{
    private final String hostName;
    private static final int port = 21;
    private final String userName;
    private final String oldPassword;
    private final String newPassword;

    // Us: Establish connection port 21
    // FTP: acknowledge 1 returned.
    // Us: send 1 acknowledge
    // send ack
    // another PSHACK with message about connection close timeout.
    // We send a PSHACK with request USER tcnedm1
    // another PSHACK with message "331 Send password please.\r\n
    // We return another ACK
    // We send PSHACK with message PASS 3dmontov/3dmontow/3dmontow\r\n
    // recv. ACK
    // Some time later another message 230-Password was changed.\r\n
    // We send PSHACK with message QUIT\r\n
    // recv. PSHACK 221 Quit command received. Goodbye.\r\n
    // connection dropped.

    /**
     *
     * @param host the value of host
     * @param name the value of name
     * @param oldPassword the value of oldPassword
     * @param newPassword the value of newPassword
     */
    public FtpPassword(String host, String name, String oldPassword, String newPassword)
    {
        this.hostName    = host;
        this.oldPassword = oldPassword;
        this.userName    = name;
        this.newPassword = newPassword;
        
        try 
        {
            try (Socket socket = new Socket(hostName, port))
            {
                PrintWriter out = new PrintWriter(socket.getOutputStream(),
                        true);
                BufferedReader in = new BufferedReader(new InputStreamReader(
                        socket.getInputStream()));
                System.out.println("FTP: "+in.readLine()); // 220-TCPIPFTP IBM FTP CS V1R11 at ESA1.DEV.OCLC.ORG, 17:13:04 on 2013-11-29.
                System.out.println("FTP: "+in.readLine()); // 220 Connection will close if idle for more than 10 minutes.
                out.print("USER " + this.userName + "\r\n");
                out.flush();
                System.out.println("FTP: "+in.readLine()); // 331 Send password please.
                out.print("PASS " + this.oldPassword 
                        + "/" + this.newPassword 
                        + "/" + this.newPassword
                        + "\r\n");
                out.flush();
                System.out.println("FTP: "+in.readLine()); // 230-Password was changed.
                System.out.println("FTP: "+in.readLine()); // 230 TCNEDM1 is logged on.  Working directory is "TCNEDM1.".
                out.print("QUIT\r\n");
                out.flush();
                System.out.println("FTP: "+in.readLine()); // Quit command received. Goodbye.
                socket.close();
            }
        } catch (UnknownHostException e) {
            System.out.println("Unknown host: " + host);
            System.exit(-1);
        } catch  (IOException e) {
            System.out.println("No I/O" + e.getMessage());
            System.exit(-1);
        }
    }
    
    /**
     * @param args the command line arguments
     */
    public static void main(String[] args)
    {
        // read the password file or take the arguments from the command line.
        PasswordFileReader pFileReader = null;
        try
        {
            pFileReader = new OCLCPasswordFile();
            String currentPassword = pFileReader.getPassword();
            String newPassword     = pFileReader.generateNewPassword();
            // new FtpPassword("edx.oclc.org", "tcnedm1", "3dmontoy", "3dmontoz");
            new FtpPassword(
                    EPLAccount.FTP_HOST,
                    EPLAccount.USER_NAME,
                    currentPassword,
                    newPassword
            );
            pFileReader.resave(newPassword);
        }
        catch (IOException ex)
        {
            Logger.getLogger(FtpPassword.class.getName()).log(Level.SEVERE, null, ex);
            System.exit(-1);
        }
    }
    
    private static class OCLCAccount
    {
        public final static String FTP_HOST = "edx.oclc.org";
    }
    /**
     * Internal class that is a simple container of EPL's user name and 
     * OCLC's FTP URL.
     */
    private final class EPLAccount extends OCLCAccount
    {
        public final static String USER_NAME = "tcnedm1";
    }
}