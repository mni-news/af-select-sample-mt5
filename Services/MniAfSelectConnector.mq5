//+------------------------------------------------------------------+
//|                                         MniAfSelectConnector.mq5 |
//|                                              Copyright 2025, MNI |
//|                                           https://alphaflash.com |
//|                 https://github.com/mni-news/af-select-sample-mt5 |
//+------------------------------------------------------------------+
#property service
#property copyright "Copyright 2025, MNI"
#property link      "https://alphaflash.com/"
#property version   "1.00"

#include <AfSelectClient.mqh>

//--- input parameters
input string   iUsername="";
input string   iPasscode="";
input string   iAuthUrl="https://api.alphaflash.com/api/auth/alphaflash-client/token";
//input string   iSelectHost="select.alphaflash.com";
input string   iSelectHost="select-test.alphaflash.com";
input int      iSelectPort=61613;
input string   iTopic="/topic/observations";
input bool     iDebugLog=false;
input int      iTlsSelectPort=61614;
input bool     iUseTls=false;

//+------------------------------------------------------------------+
//| Service program start function                                   |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("Constructing AF Select Client.");
   MNI::AfSelectClient *afSelectClient = new MNI::AfSelectClient(iAuthUrl, iSelectHost, iSelectPort, iTlsSelectPort, iUseTls, iDebugLog);
   Print("Starting AF Select Client.");
   bool started = afSelectClient.Start(iUsername, iPasscode, iTopic);

   if (started)
   {
      MNI::Observation observation;
      while(!IsStopped())
      {
         //--- This blocks until data is received, this can be an Observation or a Heartbeat.
         //--- Heartbeat receipt will return false.
         bool received_observation = afSelectClient.GetObservation(observation);
         if (received_observation)
            Print("Observation seriesId:"+observation.seriesId+" actual:"+observation.actual);
      }
   }
   else
   {
      Print("AF Select Client failed to start.");
   }
   
   
   delete afSelectClient;
   Print("Deconstructed AF Select Client.");
}

//+------------------------------------------------------------------+
