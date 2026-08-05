import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';


void main() {
  runApp(const TMapsApp());
}


class TMapsApp extends StatelessWidget {
  const TMapsApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "TMaps",
      home: const HomePage(),
    );
  }
}



class HomePage extends StatefulWidget {
  const HomePage({super.key});


  @override
  State<HomePage> createState() => _HomePageState();
}



class _HomePageState extends State<HomePage> {


  final MapController _mapController = MapController();



  LatLng currentPosition =
      const LatLng(45.0156, 78.3731);



  final List<LatLng> toilets = [

    const LatLng(
      45.02061927734114,
      78.40205998100085,
    ),

    const LatLng(
      45.027421506503714,
      78.39149158031506,
    ),

    const LatLng(
      45.02743056417113,
      78.39146797621179,
    ),

    const LatLng(
      45.022541818055785,
      78.39949128481774,
    ),

    const LatLng(
      45.01680365476963,
      78.38120726556873,
    ),

    const LatLng(
      45.004216400888026,
      78.34705805210724,
    ),

  ];



  @override
  void initState() {
    super.initState();
    getLocation();
  }





  Future<void> getLocation() async {


    bool enabled =
        await Geolocator.isLocationServiceEnabled();


    if (!enabled) {
      return;
    }



    LocationPermission permission =
        await Geolocator.checkPermission();



    if (permission ==
        LocationPermission.denied) {


      permission =
          await Geolocator.requestPermission();

    }



    if (permission ==
        LocationPermission.deniedForever) {

      return;

    }



    Position position =
        await Geolocator.getCurrentPosition(
          locationSettings:
          const LocationSettings(
            accuracy:
            LocationAccuracy.high,
          ),
        );



    setState(() {

      currentPosition =
          LatLng(
            position.latitude,
            position.longitude,
          );

    });



    _mapController.move(
      currentPosition,
      16,
    );

  }






  Future<void> addToilet() async {


    // обновляем GPS перед добавлением

    await getLocation();



    setState(() {

      toilets.add(
        currentPosition,
      );

    });



    ScaffoldMessenger.of(context)
        .showSnackBar(

      const SnackBar(

        content:
        Text(
          "🚻 Новый туалет добавлен",
        ),

      ),

    );

  }







  @override
  Widget build(BuildContext context) {


    return Scaffold(


      appBar: AppBar(

        title:
        const Text(
          "TMaps 🚻",
        ),

      ),




      floatingActionButton:


      Column(

        mainAxisAlignment:
        MainAxisAlignment.end,


        children: [



          FloatingActionButton(

            heroTag:
            "gps",


            onPressed:
            getLocation,


            child:
            const Icon(
              Icons.my_location,
            ),

          ),



          const SizedBox(
            height: 15,
          ),




          FloatingActionButton(

            heroTag:
            "add",


            backgroundColor:
            Colors.green,


            onPressed:
            addToilet,


            child:
            const Icon(
              Icons.add,
            ),

          ),


        ],

      ),






      body: FlutterMap(


        mapController:
        _mapController,



        options:
        MapOptions(

          initialCenter:
          currentPosition,


          initialZoom:
          15,

        ),





        children: [





          TileLayer(

            urlTemplate:

            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",


            userAgentPackageName:
            "com.tmaps.app",

          ),






          MarkerLayer(


            markers:


            toilets.map(

                  (toilet) {


                return Marker(


                  point:
                  toilet,


                  width:
                  45,


                  height:
                  45,


                  child:
                  const Icon(

                    Icons.wc,


                    color:
                    Colors.green,


                    size:
                    38,

                  ),


                );


              },

            ).toList(),


          ),







          MarkerLayer(


            markers: [


              Marker(


                point:
                currentPosition,


                width:
                50,


                height:
                50,


                child:
                const Icon(


                  Icons.location_on,


                  color:
                  Colors.blue,


                  size:
                  45,


                ),


              ),


            ],


          ),




        ],


      ),


    );

  }

}