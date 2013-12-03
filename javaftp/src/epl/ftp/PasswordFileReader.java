/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package epl.ftp;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Opens and reads a password file. There be as many lines that start with '#' 
 * which are ignored as comments. Once the first non-comment line is read it is
 * expected to be the password. While all comment lines are ignored, all lines 
 * before the password is encountered are re-saved to the password file if the 
 * password file is re-saved. No comments after the password will be re-saved.
 * @author andrew
 */
public abstract class PasswordFileReader
{
    private String password;
    private List<String> comments;
    private String path;
    
    /**
     * Opens and reads first non-comment ('#') line as the stored password.
     * @param path fully qualified path of the password file.
     * @throws IOException 
     */
    protected PasswordFileReader(String path) throws IOException
    {
        this.path = path;
        this.comments = new ArrayList<>();
        BufferedReader br = null;
        try 
        {
            String sCurrentLine;
            br = new BufferedReader(new FileReader(path));
            while ((sCurrentLine = br.readLine()) != null) 
            {
                System.out.println(sCurrentLine);
                if (sCurrentLine.startsWith("#"))
                {
                    comments.add(sCurrentLine);
                }
                else
                {
                    this.password = sCurrentLine.trim();
                    break; // anything after the password is not saved.
                }
            }

        } 
        finally 
        {
            if (br != null)br.close();
        }
    }
    
    /**
     * Gets the password saved in the password file.
     * @return stored password string.
     */
    public String getPassword()
    {
        return this.password;
    }
    
    /**
     * Re-saves the argument password to file.
     * @param newPassword
     * @return true if the save was successful and false if there was an 
     * IOException.
     */
    public boolean resave(String newPassword)
    {
        this.password = newPassword;
        try 
        {
            File file = new File(this.path);
            FileWriter fw = new FileWriter(file.getAbsoluteFile());
            BufferedWriter bw = new BufferedWriter(fw);
            for(String comment: this.comments)
            {
                bw.write(comment);
                bw.write("\n");
            }
            bw.write(this.password);
            bw.close();
            System.out.println("Done");
        } 
        catch (IOException e) 
        {
            return false;
        }
        return true;
    }
    
    public abstract String generateNewPassword();
}
