//+------------------------------------------------------------------+
//|                                               AfSelectClient.mqh |
//|                                              Copyright 2025, MNI |
//|                                           https://alphaflash.com |
//|                 https://github.com/mni-news/af-select-sample-mt5 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MNI"
#property link      "https://alphaflash.com"
#property version   "1.00"

#include <Jason.mqh>

namespace MNI 
{
   struct Observation {
       int seriesId;
       double actual;
       string eventDate;
   };
   
   class AfSelectClient
   {
   
     public:
         AfSelectClient(const string authUrl, const string selectHost, int selectPort, int selectTlsPort, bool useTls=true, bool debugLog=false);
         ~AfSelectClient();
         bool Start(const string username, const string passcode, const string topic = "/topic/observations");
         bool AfSelectClient::GetObservation(Observation &observation);
         void Stop();
            
      private:
         string   auth_url_;
         string   select_host_;
         int      select_port_;
         int      select_tls_port_;
         string   username_;
         string   passcode_;
         string   topic_;
         bool     debug_log_;
         bool     use_tls_;
         string   token_;
         int      socket_;
         bool     running_;
                  
         string   getAuthToken();
         bool     connect();
         bool     subscribe();
         string   readStompMessage();
         string   readUntil(char delimiter);
         bool     reconnect();
         bool     tlsHandshake(int socket);
   };
   
   
   
   //+------------------------------------------------------------------+
   //| AfSelectClient constructor
   //+------------------------------------------------------------------+
   AfSelectClient::AfSelectClient(const string authUrl, const string selectHost, int selectPort, int selectTlsPort, bool useTls, bool debugLog)
   {
      auth_url_ = authUrl;
      select_host_ = selectHost;
      select_port_ = selectPort;
      select_tls_port_ = selectTlsPort;
      use_tls_ = useTls;
      debug_log_ = debugLog;
   }
     
   //+------------------------------------------------------------------+
   //| AfSelectClient destructor
   //+------------------------------------------------------------------+
   AfSelectClient::~AfSelectClient()
   {
   }


   //+------------------------------------------------------------------+
   //| AfSelectClient Start - authenticate, stomp connect and subscribe 
   //+------------------------------------------------------------------+
   bool AfSelectClient::Start(const string username, const string passcode, const string topic = "/topic/observations")
   {
      username_ = username;
      passcode_ = passcode;
      topic_ = topic;
      
      running_ = true;
      
      Print("Retrieving auth token.");
      token_ = getAuthToken();
      if (token_ == NULL)
         return false;
      
      if (!connect())
         return false;
      
      subscribe();
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| AfSelectClient GetObservation - wait for an observation to be set, 
   //| returns true if the observation was set
   //| return fasle if there was a timeout (based on heartbeat receipt)
   //+------------------------------------------------------------------+
   bool AfSelectClient::GetObservation(Observation &observation)
   {
      string stomp_message = readStompMessage();
      if (stomp_message == NULL)
      {
         reconnect();
         return false;
      }
      
      if (StringCompare(stomp_message, "HB") != 0)
      {
         if (debug_log_) Print("STOMP: "+stomp_message);
         
         // last line is the body with json
         string lines[];
         int number_of_lines = StringSplit(stomp_message,StringGetCharacter("\n",0),lines);
         int len = StringLen(lines[number_of_lines-1]);
         string body = StringSubstr(lines[number_of_lines-1],1,len-2);
         if (debug_log_) Print("STOMP Body: "+body);
         
         // convert line to json and set observation values
         CJAVal json;
         if (json.Deserialize(body)){
            observation.seriesId = (int)json["dataSeriesId"].ToInt();
            observation.actual = json["value"].ToDbl();
            observation.eventDate = json["eventDate"].ToStr();
            return true;
         }
      }
        
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| AfSelectClient Stop - stop the client and cleanup resources
   //+------------------------------------------------------------------+
   void AfSelectClient::Stop()
   {
      running_ = false;
      if (SocketIsConnected(socket_)) {
         SocketClose(socket_);
      }
   }


   //+------------------------------------------------------------------+
   //| AfSelectClient private getAuthToken - get an AUTH token to be used 
   //| for stomp client access
   //| return the token on successful login
   //| rerurn NULL on logon faulure   
   //+------------------------------------------------------------------+
   string AfSelectClient::getAuthToken()
   {
      CJAVal body;
      body["username"] = username_;
      body["password"] = passcode_;
      
      char data[];
      ArrayResize(data, StringToCharArray(body.Serialize(), data, 0, WHOLE_ARRAY)-1);
   
      char result[];
      string result_headers;
      int response = WebRequest("POST", auth_url_, "Content-Type: application/json", 500, data, result, result_headers);
   
      CJAVal json;
      switch(response)
      {
         case -1:
            Print("Please add '"+auth_url_+"' to allowed urls in Tools/Options. Error code = ", GetLastError());
            break;
         case 200:
            json.Deserialize(CharArrayToString(result));
            Print("WebRequest return code 200.");
            break;
         default:
            Print(StringFormat(__FUNCTION__+" failed - error code %d", response));
            return NULL;
      }
   
      return json["access_token"].ToStr();
   }
   
   //+------------------------------------------------------------------+
   //| AfSelectClient private connect - establish a conneced socket 
   //| (plain or tls) to the stomp endpoint
   //| return true if connected successfully
   //+------------------------------------------------------------------+   
   bool AfSelectClient::connect()
   {
      socket_ = SocketCreate();
      SocketTimeouts(socket_,30000,60000);
      int port = (use_tls_ ? select_tls_port_ : select_port_);
      if(socket_!=INVALID_HANDLE)
      {    
         if(SocketConnect(socket_,select_host_, port, 10000))
         {
            Print("Established connection to ",select_host_,":", port);   
            
            if (use_tls_)
               tlsHandshake(socket_);            
                     
            string connect_frame = "CONNECT\naccept-version:1.0\nheart-beat:0,30000\npasscode:" + token_ + "\n\n\0";
            char req[];
            int  len=StringToCharArray(connect_frame,req)-1;           
            if (len == (use_tls_ ? SocketTlsSend(socket_,req,len) : SocketSend(socket_,req,len)))
            {            
               Print("CONNECT/AUTH sent.");
               char   rsp[];
               string result;
               int rsp_len;
               
               do
               {
                  if (debug_log_) Print("CONNECT/AUTH reading.");
                  rsp_len = (use_tls_ ? SocketTlsRead(socket_,rsp,1) : SocketRead(socket_,rsp,1,10000));
                  if (debug_log_) Print("CONNECT/AUTH read "+IntegerToString(rsp_len)+" bytes.");
                  if(rsp_len>0)
                  {
                     if (debug_log_) Print("CONNECT/AUTH read byte:"+CharToString(rsp[0]));
                     result+=CharArrayToString(rsp);                     
                  }
                  else
                  {
                     Print("Failed to get a CONNECT/AUTH response, error ",GetLastError());
                     return false;
                  }
                  
               }while(rsp[0] != NULL);
               
               Print("CONNECT/AUTH complete, result:"+result);
               return true;
            }
         }
         
         return false;
      }
      else
      {
         Print("Failed to create a socket, error ",GetLastError());
         return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| AfSelectClient private subscribe - sent SUBSCRIBE to stomp endpoint
   //| return true is subscribed successfully
   //+------------------------------------------------------------------+   
   bool AfSelectClient::subscribe()
   {
      Print("Subscribing to ",topic_);            
      string subscribe_frame = "SUBSCRIBE\ndestination:" + topic_ + "\n\n\0";
      char req[];
      int  len=StringToCharArray(subscribe_frame,req)-1;
      if (len == (use_tls_ ? SocketTlsSend(socket_,req,len) : SocketSend(socket_,req,len)))
      {            
         Print("SUBSCRIBE sent.");
         return true;
      }
      
      return false;
   }

   //+------------------------------------------------------------------+
   //| AfSelectClient private readStompMessage - read a string from stomp
   //| return null if a read-timout occurs
   //| return constant HB if a heaerbeat message was read
   //| return the null terminated string received from stomp
   //+------------------------------------------------------------------+
   string AfSelectClient::readStompMessage()
   {
      string initial_stomp_message = readUntil('\n');
      if (initial_stomp_message == NULL)
      {
         return NULL; //indicates a read timeout needing reconnect
      }
      
      if (initial_stomp_message.Length() == 1)
      {
         if (debug_log_) Print("STOMP HEARTBEAT.");
         return "HB"; //  return HB string
      }
      
      string completion_stomp_message = readUntil('\0');
      if (completion_stomp_message == NULL)
      {
         return NULL; //indicates a read timeout needing reconnect
      }
      
      initial_stomp_message += completion_stomp_message;
      return initial_stomp_message;
   }

   //+------------------------------------------------------------------+
   //| AfSelectClient private readUntil - helper to read stomp stream
   //| until the specified delimiter is received (null or newline)
   //+------------------------------------------------------------------+
   string AfSelectClient::readUntil(char delimiter)
   {
      char   rsp[];
      string result;
      int rsp_len;
      
      do
      {
         if (debug_log_) Print("STOMP reading.");
         rsp_len = (use_tls_ ? SocketTlsRead(socket_,rsp,1) : SocketRead(socket_,rsp,1,60000));
         if (debug_log_) Print("STOMP read "+IntegerToString(rsp_len)+" bytes.");
         if(rsp_len>0)
         {
            if (debug_log_) Print("STOMP read byte:"+CharToString(rsp[0]));
            result+=CharArrayToString(rsp);                     
         }
         
         if(rsp_len==-1)
         {
            Print("STOMP read timeout, socket is connected:"+(string)SocketIsConnected(socket_));
            return NULL;
         } 
         
      }while(rsp[0] != delimiter);
      
      return result;
   }

   //+------------------------------------------------------------------+
   //| AfSelectClient private reconnect - reconnect in case of connection failure
   //| get AUTH token, connect and subscribe
   //| retry at fixed 30 second intervals
   //| return true on reconnect
   //| return false if the client is stopped 
   //+------------------------------------------------------------------+
   bool AfSelectClient::reconnect()
   {
      if (IsStopped())
         return false;
   
      Print("Reconnecting.");
      
      token_ = NULL;
      do
      {
         token_ = getAuthToken();
         if (token_ == NULL)
            Sleep(30000);
            
         if (IsStopped())
            return false;
         
      }while(token_ == NULL && running_ == true);
      
      bool connected = false;
      do
      {
         connected = connect();
         if (connected == false)
            Sleep(30000);
            
         if (IsStopped())
            return false;   
         
      }while(connected == false && running_ == true);
      
      if (connected && running_)
      {
         if (subscribe())
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| AfSelectClient private tlsHandshake - setup tls on the socket to 
   //| stomp endpoint
   //+------------------------------------------------------------------+   
   bool AfSelectClient::tlsHandshake(int socket)
   {
      
      //--- initiate a secure TLS (SSL) connection to the specified host using the TLS Handshake protocol
      if(SocketTlsHandshake(socket,select_host_))
      {  
         string   subject,issuer,serial,thumbprint;
         datetime expiration;
         //--- if connection is secured by the certificate, display its data
         if(SocketTlsCertificate(socket,subject,issuer,serial,thumbprint,expiration))
           {
            Print("TLS certificate:");
            Print("   Owner:   ",subject);
            Print("   Issuer:  ",issuer);
            Print("   Number:  ",serial);
            Print("   Print:   ",thumbprint);
            Print("   Expiration: ",expiration);
           }
           
         return(true);
      }
      
      Print("SocketTlsHandshake() failed. Error ",GetLastError());
      return(false);
  }
  
} // namespace MNI